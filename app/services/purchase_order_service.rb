# app/services/purchase_order_service.rb
require "tempfile"
class PurchaseOrderService
  class PurchaseOrderError < StandardError; end

  # Applied to every photographed page before it's combined into the PDF —
  # deskew from EXIF orientation, cap the resolution (the browser already
  # downscales to ~2000px, this is the backstop for anything that arrives via
  # another route), drop colour noise, even out lighting/shadows from a phone
  # photo, then a light sharpen so text stays legible after grayscale.
  # Cloudinary applies these server-side via the `multi` transform, so no local
  # image-processing gem is needed (none is in the Gemfile).
  IMAGE_CLEANUP_TRANSFORMATION = [
    { angle: "exif" },
    { width: 1400, height: 1400, crop: "limit" },
    { effect: "grayscale" },
    { effect: "improve" },
    { effect: "contrast:25" },     # pushes paper towards white, kills grain
    { effect: "sharpen:60" },
    { quality: "auto:eco" }
  ].freeze

  # First-page thumbnail for the order page card — same size and crop as the
  # drawing thumbnails on the works order page. Built at attach time and
  # stored in po_document["thumbnail_url"], because that's the only moment
  # we know what the asset actually is (a PDF page vs a scanned image).
  THUMBNAIL_TRANSFORMATION = { width: 224, height: 288, crop: "fill", gravity: "north", quality: "auto" }.freeze

  # ---------------------------------------------------------------------------
  # Called from the AI assistant (via execute_query) after it creates a
  # CustomerOrder from an uploaded PO.
  #
  # The request's attachments are "hams_file" reference blocks (see
  # AssistantAttachments): the bytes are already in Cloudinary, so this is
  # the same no-bytes path the email intake uses — a PDF is copied into the
  # customer's folder server-side, photographed pages are tagged and combined
  # into one cleaned multi-page PDF by Cloudinary. No bytes pass through
  # the worker, and it can run on any later turn, not just the one the
  # files were attached in.
  #
  # PDF attachments win over images; mixed uploads aren't a case this
  # handles — if that turns out to matter in practice, it needs its own
  # decision.
  #
  # Usage from AI assistant:
  #   PurchaseOrderService.attach_from_request(
  #     customer_order_id: co.id,
  #     request_id: @request_id
  #   )
  # ---------------------------------------------------------------------------
  def self.attach_from_request(customer_order_id:, request_id:)
    customer_order = CustomerOrder.find(customer_order_id)
    request        = AiAssistantRequest.find(request_id)

    pdfs   = request.pdf_attachments
    images = request.image_attachments

    if pdfs.empty? && images.empty?
      raise PurchaseOrderError, "No PDF or image attachments found in the request messages."
    end

    result = pdfs.any? ? copy_pdf(pdfs.first, customer_order) : adopt_images(images, customer_order)

    store!(customer_order, result, source: pdfs.any? ? "pdf" : "scanned_images")

    {
      success: true,
      url: result[:secure_url],
      pages_combined: pdfs.any? ? nil : images.length,
      customer_order_number: customer_order.number
    }.compact
  rescue => e
    Rails.logger.error "[PurchaseOrderService] attach_from_request error: #{e.message}"
    { success: false, error: e.message }
  end

  # ---------------------------------------------------------------------------
  # Manual path — the PO/edit form's file field, for POs that arrive by email
  # as a ready-made PDF. `file` is the raw Rack::Test::UploadedFile /
  # ActionDispatch::Http::UploadedFile from params.
  # ---------------------------------------------------------------------------
  def self.attach_upload(customer_order:, file:)
    raise PurchaseOrderError, "No file given" if file.blank?

    tempfile = file.respond_to?(:tempfile) ? file.tempfile : file

    # PDFs go up as resource_type "image" (not "raw"): Cloudinary delivers
    # them identically, but only image-type assets can be page-transformed,
    # which is what the pg_1 thumbnail needs. (Raw would work for delivery
    # alone — that's how it used to be — but leaves no way to preview.)
    uploaded = Cloudinary::Uploader.upload(
      tempfile.path,
      public_id: "#{folder_path(customer_order)}/#{file_prefix(customer_order)}",
      resource_type: "image",
      overwrite: true,
      unique_filename: false
    )

    result = {
      public_id:     uploaded["public_id"],
      secure_url:    uploaded["secure_url"],
      format:        uploaded["format"],
      bytes:         uploaded["bytes"],
      thumbnail_url: page_thumbnail_url(uploaded["public_id"])
    }

    store!(customer_order, result, source: "upload")
    result
  end


  # ---------------------------------------------------------------------------
  # Email path — the PO arrived at orders@ and PoIntakeJob has already parked
  # the attachments in Cloudinary under inbound_purchase_orders/<id>/. Unlike
  # attach_from_request this can run any time later (review page, console),
  # because it reads from Cloudinary, not from the assistant request.
  #
  # Which attachment: `attachment_index` if given, else the assistant's
  # po_attachment_index, else the first PDF, else all images combined.
  # ---------------------------------------------------------------------------
  def self.attach_from_inbound(customer_order:, inbound_purchase_order:, attachment_index: nil)
    ipo   = inbound_purchase_order
    index = attachment_index || ipo.proposal["po_attachment_index"]
    chosen = index.present? ? ipo.attachments.find { |a| a["index"] == index.to_i } : nil
    chosen ||= ipo.pdf_attachments.first

    result =
      if chosen
        raise PurchaseOrderError, "Attachment #{chosen['name']} was never parked in Cloudinary" if chosen["public_id"].blank?
        chosen["content_type"] == "application/pdf" ? adopt_pdf(chosen, customer_order) : adopt_images([chosen], customer_order)
      elsif ipo.image_attachments.any?
        adopt_images(ipo.image_attachments, customer_order)
      else
        raise PurchaseOrderError, "No PDF or image attachment on inbound PO #{ipo.id}"
      end

    store!(customer_order, result, source: "email")
    result
  end

  # Move the parked PDF into the customer's purchase_orders folder. rename is
  # a metadata operation — no re-upload.
  def self.adopt_pdf(att, customer_order)
    new_id  = "#{folder_path(customer_order)}/#{file_prefix(customer_order)}"
    renamed = Cloudinary::Uploader.rename(att["public_id"], new_id, resource_type: "image", overwrite: true)

    { public_id: renamed["public_id"], secure_url: renamed["secure_url"],
      format: "pdf", bytes: renamed["bytes"],
      thumbnail_url: page_thumbnail_url(renamed["public_id"]) }
  end
  private_class_method :adopt_pdf

  # Same destination, but the source stays where it is: assistant uploads
  # live at ai_assistant/<user>/<hash> and are referenced from the request
  # (and the de-dupe cache), so they must not be renamed away. Cloudinary
  # fetches the source URL itself — no bytes through the worker.
  def self.copy_pdf(att, customer_order)
    uploaded = Cloudinary::Uploader.upload(
      att["secure_url"],
      public_id:       "#{folder_path(customer_order)}/#{file_prefix(customer_order)}",
      resource_type:   "image",
      overwrite:       true,
      unique_filename: false
    )

    { public_id: uploaded["public_id"], secure_url: uploaded["secure_url"],
      format: "pdf", bytes: uploaded["bytes"],
      thumbnail_url: page_thumbnail_url(uploaded["public_id"]) }
  end
  private_class_method :copy_pdf

  # Parked photos (inbound email or assistant upload — both already in
  # Cloudinary) → cleaned multi-page PDF. Tags the existing assets and lets
  # Cloudinary's `multi` assemble and clean them; nothing is downloaded.
  def self.adopt_images(atts, customer_order)
    tag      = "po_#{customer_order.id}_#{SecureRandom.hex(4)}"
    page_ids = atts.map { |a| a["public_id"] }
    Cloudinary::Uploader.add_tag(tag, page_ids, resource_type: "image")

    combined = Cloudinary::Uploader.multi(
      tag,
      format: "pdf",
      transformation: IMAGE_CLEANUP_TRANSFORMATION.map(&:dup)
    )

    { public_id: combined["public_id"], secure_url: combined["secure_url"],
      format: "pdf", bytes: combined["bytes"],
      thumbnail_url: scan_thumbnail_url(page_ids.first) }
  end
  private_class_method :adopt_images

  # ---------------------------------------------------------------------------
  # Book the PO's line items in as works orders. The structured `lines` come
  # from the intake assistant's proposal (or a reviewer's edits):
  #
  #   [{ "part_id" => uuid | nil, "part_number" => "...", "part_issue" => "...",
  #      "quantity" => 10, "unit_price" => 4.5 | nil, "customer_reference" => "...",
  #      "rework" => false, "free_of_charge" => false, "operation_note" => "..." }, ...]
  #
  # Rework lines get "REWORK" in the customer reference and, when the PO
  # prices them at zero, book as a £0 lot without touching the part's
  # each_price (WorksOrder only writes back `each` prices > 0).
  #
  # One transaction — either every line books or none do, and the error says
  # which line and why. A works order carries the TRUE price only: the part's
  # saved each_price if it has one, else the PO's, else a £0 lot for contract
  # review to fix. Where the part has a price and the PO states a different
  # one, the WO is flagged so CR queries it. Minimum charges are NOT applied here — the caller runs
  # MinimumCharges.apply!(customer_order) once every line is booked, which
  # puts the customer's per-order / per-WO minimums on as top-up charges.
  #
  # No acknowledgement is sent here either: it goes out when contract review
  # is signed off (WorksOrder#acknowledge_order!). The acknowledge: keyword is
  # accepted and ignored so older callers keep working.
  # ---------------------------------------------------------------------------
  def self.book_lines!(customer_order:, lines:, acknowledge: nil)
    lines = Array(lines).map { |l| l.to_h.stringify_keys }
    raise PurchaseOrderError, "No lines to book" if lines.empty?

    created = []
    CustomerOrder.transaction do
      lines.each_with_index do |line, i|
        label = "line #{i + 1} (#{line['part_number']}#{line['part_issue'].present? ? "/#{line['part_issue']}" : ''})"
        part  = resolve_part!(customer_order, line, label)
        qty   = line["quantity"].to_i
        raise PurchaseOrderError, "#{label}: quantity must be positive" unless qty.positive?

        rework = ActiveModel::Type::Boolean.new.cast(line["rework"])
        free   = ActiveModel::Type::Boolean.new.cast(line["free_of_charge"]) || (rework && line["unit_price"].to_d.zero?)

        reference = line["customer_reference"].to_s
        reference = ["REWORK", reference.presence].compact.join(" — ") if rework && !reference.match?(/rework/i)

        pricing = free ? { price_type: "lot", lot_price: 0 } : price_attributes(part, qty, line["unit_price"])
        wo = WorksOrder.new(
          customer_order:     customer_order,
          part:               part,
          quantity:           qty,
          customer_reference: reference.first(100).presence,
          **pricing
        )
        wo.save! # raises with the WorksOrder's own validation messages
        created << wo

        # Shop-floor instruction from the PO (strip details, "omit seal on
        # painted faces", "do not etch") and, when neither the PO nor the
        # part gave a price, the unpriced warning. Both go on booking_notes -
        # NOT as an operation note, which would freeze the process record and
        # stop the WO joining a process group. Shown in the special
        # instructions box on the WO page and route card.
        notes = []
        notes << UNPRICED_WARNING if !free && pricing[:lot_price].to_d.zero?
        notes << price_mismatch_warning(part, line["unit_price"]) if !free && price_mismatch?(part, line["unit_price"])
        notes << "From customer PO: #{line['operation_note']}".first(2000) if line["operation_note"].present?
        wo.update_column(:booking_notes, notes.join("\n\n")) if notes.any?
      end
    end

    created
  end

  UNPRICED_WARNING = "** DO NOT SIGN-OFF CONTRACT REVIEW UNTIL YOU REVIEW THE UNIT PRICE/LOT PRICE; " \
                     "MOC BLINDLY APPLIED. ORDER CONFIRMATION NOT YET SENT (HAPPENS AT CR SIGN-OFF) **".freeze

  # Exactly one enabled, fully configured part — by id if the proposal has
  # one, else by Part.matching. Anything else raises with a reason a
  # reviewer can act on.
  def self.resolve_part!(customer_order, line, label)
    part =
      if line["part_id"].present?
        Part.find_by(id: line["part_id"])
      else
        matches = Part.matching(customer_id: customer_order.customer_id,
                                part_number: line["part_number"].to_s,
                                part_issue:  line["part_issue"].to_s).to_a
        raise PurchaseOrderError, "#{label}: #{matches.size} parts match — ambiguous" if matches.size > 1
        matches.first
      end

    raise PurchaseOrderError, "#{label}: part not found for #{customer_order.customer.name}" unless part
    raise PurchaseOrderError, "#{label}: #{part.display_name} belongs to #{part.customer&.name}, not #{customer_order.customer.name}" if part.customer_id != customer_order.customer_id
    raise PurchaseOrderError, "#{label}: #{part.display_name} is disabled" if part.respond_to?(:enabled) && part.enabled == false
    if part.customisation_data.blank? || part.customisation_data.dig("operation_selection", "treatments").blank?
      raise PurchaseOrderError, "#{label}: #{part.display_name} has no processing instructions configured"
    end
    part
  end
  private_class_method :resolve_part!

  # The part's saved each_price wins: that's our agreed price, and a PO
  # stating something else is a query for contract review, not a reason to
  # book at it (booking at the PO price would also write it back onto the
  # part - see WorksOrder - silently replacing ours). The PO price is the
  # fallback for a part with no price yet, else £0 (lot) — the reviewer sees
  # a £0 line and prices it. No minimum-charge floor here.
  def self.price_attributes(part, qty, po_unit_price)
    each = saved_each_price(part) || positive_decimal(po_unit_price)
    if each&.positive?
      { price_type: "each", each_price: each, lot_price: (each * qty).round(2) }
    else
      { price_type: "lot", lot_price: 0 }
    end
  end
  private_class_method :price_attributes

  def self.price_mismatch?(part, po_unit_price)
    saved = saved_each_price(part)
    po    = positive_decimal(po_unit_price)
    saved && po && saved != po
  end
  private_class_method :price_mismatch?

  def self.price_mismatch_warning(part, po_unit_price)
    "** PRICE QUERY: customer PO states £#{'%.2f' % positive_decimal(po_unit_price)} each for " \
    "#{part.display_name}; booked at our saved price of £#{'%.2f' % saved_each_price(part)} each. " \
    "QUERY WITH THE CUSTOMER BEFORE CR SIGN-OFF **"
  end
  private_class_method :price_mismatch_warning

  def self.saved_each_price(part)
    positive_decimal(part.each_price)
  end
  private_class_method :saved_each_price

  def self.positive_decimal(value)
    return nil if value.blank?
    d = value.to_d
    d.positive? ? d : nil
  end
  private_class_method :positive_decimal

  # ---------------------------------------------------------------------------
  # Drawings that arrived alongside the PO → the part's file list, in the
  # shape Part#upload_file writes (same as QuoteService.share_drawings!). The
  # parked Cloudinary asset is referenced, not re-uploaded. A file the part
  # already has by name is skipped, so a customer re-attaching the same
  # drawing on every order doesn't pile up copies.
  # ---------------------------------------------------------------------------
  def self.attach_drawings!(part:, inbound_purchase_order:, indexes:)
    ipo   = inbound_purchase_order
    atts  = Array(indexes).map(&:to_i).filter_map { |i| ipo.attachments.find { |a| a["index"] == i } }
    atts  = atts.select { |a| a["public_id"].present? && !a["inline"] }
    return [] if atts.empty?

    data  = (part.customisation_data || {}).deep_dup
    files = data["files"] || []
    have_ids   = files.map { |f| f["cloudinary_public_id"] }
    have_names = files.map { |f| f["original_filename"].to_s.downcase }
    added = []

    atts.each do |a|
      next if have_ids.include?(a["public_id"]) || have_names.include?(a["name"].to_s.downcase)
      files << {
        "cloudinary_public_id" => a["public_id"],
        "cloudinary_url"       => a["secure_url"],
        "original_filename"    => a["name"],
        "file_size_bytes"      => a["bytes"] || a["size"],
        "content_type"         => a["content_type"],
        "uploaded_at"          => Time.current.iso8601,
        "source"               => "po_email:#{ipo.id}"
      }
      added << a["name"]
    end

    if added.any?
      data["files"] = files
      part.update!(customisation_data: data)
    end
    added
  end

  # ---------------------------------------------------------------------------




  # Page 1 of an image-type PDF asset as a JPEG.
  # Cloudinary::Utils.cloudinary_url MUTATES the transformation hashes it is
  # given (it deletes keys as it consumes them), so the frozen constants must
  # be deep-copied on every call — "can't modify frozen Hash" otherwise.
  def self.page_thumbnail_url(public_id)
    Cloudinary::Utils.cloudinary_url(
      public_id,
      resource_type: "image", format: "jpg", secure: true,
      transformation: [{ page: 1 }, THUMBNAIL_TRANSFORMATION.dup]
    )
  end
  private_class_method :page_thumbnail_url

  # The kept first-page scan, cleaned the same way the PDF pages were, then
  # thumbnailed — so the card matches the document it opens.
  def self.scan_thumbnail_url(page_public_id)
    return if page_public_id.blank?
    Cloudinary::Utils.cloudinary_url(
      page_public_id,
      resource_type: "image", format: "jpg", secure: true,
      transformation: IMAGE_CLEANUP_TRANSFORMATION.map(&:dup) + [THUMBNAIL_TRANSFORMATION.dup]
    )
  end
  private_class_method :scan_thumbnail_url

  def self.store!(customer_order, result, source:)
    customer_order.update!(
      po_document: {
        "public_id"     => result[:public_id],
        "secure_url"    => result[:secure_url],
        "format"        => result[:format],
        "bytes"         => result[:bytes],
        "thumbnail_url" => result[:thumbnail_url],
        "source"        => source,
        "attached_at"   => Time.current.iso8601
      }.compact
    )
  end
  private_class_method :store!

  def self.folder_path(customer_order)
    "purchase_orders/#{customer_order.customer.name.parameterize}"
  end
  private_class_method :folder_path

  def self.file_prefix(customer_order)
    "#{customer_order.number.to_s.parameterize}_#{Time.current.strftime('%Y%m%d_%H%M%S')}"
  end
  private_class_method :file_prefix
end
