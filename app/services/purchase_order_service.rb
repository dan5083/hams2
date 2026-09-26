# app/services/purchase_order_service.rb
require "tempfile"
require "base64"

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
  # IMPORTANT — must be called in the same assistant run the files were
  # uploaded in. AiAssistantRequest#mark_complete!/#mark_error! strip base64
  # data out of stored messages once the job finishes (see
  # ai_assistant_request.rb#strip_base64_from_messages!), so this has nothing
  # to read on a later turn.
  #
  # PDF attachments are stored as-is. Photographed pages (one or more images)
  # are cleaned up and combined into a single multi-page PDF. If a message
  # contains both, the PDF wins and the images are ignored — mixed uploads
  # aren't a case this handles; if that turns out to matter in practice, it
  # needs its own decision.
  #
  # Usage from AI assistant:
  #   PurchaseOrderService.attach_from_request(
  #     customer_order_id: co.id,
  #     request_id: @request_id
  #   )
  # ---------------------------------------------------------------------------
  def self.attach_from_request(customer_order_id:, request_id:)
    customer_order = CustomerOrder.find(customer_order_id)
    request = AiAssistantRequest.find(request_id)

    pdf_blocks   = []
    image_blocks = []

    request.messages.each do |msg|
      content = msg["content"]
      next unless content.is_a?(Array)

      content.each do |block|
        source = block["source"]
        next unless source&.dig("type") == "base64" && source["data"].present?

        media_type = source["media_type"].to_s
        if media_type == "application/pdf"
          pdf_blocks << source["data"]
        elsif media_type.start_with?("image/")
          image_blocks << source["data"]
        end
      end
    end

    if pdf_blocks.empty? && image_blocks.empty?
      raise PurchaseOrderError, "No PDF or image attachments found in the request messages."
    end

    result =
      if pdf_blocks.any?
        upload_pdf(pdf_blocks.first, customer_order)
      else
        upload_images_as_pdf(image_blocks, customer_order)
      end

    store!(customer_order, result, source: pdf_blocks.any? ? "pdf" : "scanned_images")

    {
      success: true,
      url: result[:secure_url],
      pages_combined: pdf_blocks.any? ? nil : image_blocks.length,
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

  # Parked photos → cleaned multi-page PDF, same as upload_images_as_pdf but
  # tagging the assets that already exist instead of uploading them again.
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
  #      "quantity" => 10, "unit_price" => 4.5 | nil, "customer_reference" => "..." }, ...]
  #
  # One transaction — either every line books or none do, and the error says
  # which line and why. Pricing follows the same rules the chat assistant and
  # the WO form apply: PO price if stated, else the part's each_price, with
  # the MOC as a floor; no price at all → lot at the MOC.
  #
  # Sends the order acknowledgement exactly as WorksOrdersController#create_bulk
  # does (inline, best-effort), unless acknowledge: false.
  # ---------------------------------------------------------------------------
  MOC_STANDARD            = 250.to_d
  MOC_CHEMICAL_CONVERSION = 125.to_d

  def self.book_lines!(customer_order:, lines:, issued_by: nil, acknowledge: true)
    lines = Array(lines).map { |l| l.to_h.stringify_keys }
    raise PurchaseOrderError, "No lines to book" if lines.empty?

    created = []
    CustomerOrder.transaction do
      lines.each_with_index do |line, i|
        label = "line #{i + 1} (#{line['part_number']}#{line['part_issue'].present? ? "/#{line['part_issue']}" : ''})"
        part  = resolve_part!(customer_order, line, label)
        qty   = line["quantity"].to_i
        raise PurchaseOrderError, "#{label}: quantity must be positive" unless qty.positive?

        wo = WorksOrder.new(
          customer_order:     customer_order,
          part:               part,
          quantity:           qty,
          customer_reference: line["customer_reference"].to_s.first(100).presence,
          issued_by:          issued_by,
          **price_attributes(part, qty, line["unit_price"])
        )
        wo.save! # raises with the WorksOrder's own validation messages
        created << wo
      end
    end

    if acknowledge && customer_order.customer.buyer_emails.any?
      begin
        OrderAcknowledgementMailer.order_confirmation(customer_order, created).deliver_now
      rescue => e
        Rails.logger.error "[PurchaseOrderService] acknowledgement failed for order #{customer_order.number}: #{e.message}"
      end
    end

    created
  end

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

  def self.price_attributes(part, qty, po_unit_price)
    moc  = moc_for(part)
    each = po_unit_price.present? && po_unit_price.to_d.positive? ? po_unit_price.to_d : part.each_price&.to_d

    if each&.positive?
      total = (each * qty).round(2)
      if total < moc
        { price_type: "lot", lot_price: moc }
      else
        { price_type: "each", each_price: each, lot_price: total }
      end
    else
      { price_type: "lot", lot_price: moc }
    end
  end
  private_class_method :price_attributes

  # £125 MOC when the part is chemical conversion only; £250 otherwise.
  def self.moc_for(part)
    raw   = part.customisation_data.dig("operation_selection", "treatments")
    types = (raw.is_a?(String) ? JSON.parse(raw) : Array(raw)).map { |t| t["type"] }.compact.uniq rescue []
    types == ["chemical_conversion"] ? MOC_CHEMICAL_CONVERSION : MOC_STANDARD
  end
  private_class_method :moc_for

  # ---------------------------------------------------------------------------

  def self.upload_pdf(base64_data, customer_order)
    with_tempfile("po", ".pdf", base64_data) do |tempfile|
      uploaded = Cloudinary::Uploader.upload(
        tempfile.path,
        public_id: "#{folder_path(customer_order)}/#{file_prefix(customer_order)}",
        resource_type: "image", # see attach_upload — enables the page-1 thumbnail
        overwrite: true,
        unique_filename: false
      )

      { public_id: uploaded["public_id"], secure_url: uploaded["secure_url"],
        format: "pdf", bytes: uploaded["bytes"],
        thumbnail_url: page_thumbnail_url(uploaded["public_id"]) }
    end
  end
  private_class_method :upload_pdf

  def self.upload_images_as_pdf(base64_images, customer_order)
    tag      = "po_#{customer_order.id}_#{SecureRandom.hex(4)}"
    page_ids = []

    base64_images.each do |data|
      with_tempfile("po_page", ".jpg", data) do |tempfile|
        uploaded = Cloudinary::Uploader.upload(
          tempfile.path,
          folder: "#{folder_path(customer_order)}/pages",
          tags: [tag],
          overwrite: true
        )
        page_ids << uploaded["public_id"]
      end
    end

    # Combines every image tagged above into one multi-page PDF, applying the
    # cleanup transformation to each page as it's assembled. Page order follows
    # upload order, i.e. the order the files were attached in.
    combined = Cloudinary::Uploader.multi(
      tag,
      format: "pdf",
      transformation: IMAGE_CLEANUP_TRANSFORMATION.map(&:dup)
    )

    # The combined PDF is its own stored asset (type "multi"), so the page
    # originals are dead weight once it exists — except page 1, which is kept
    # as the source of the order page thumbnail (a multi asset can't be
    # page-transformed). Best-effort — a failure here shouldn't lose the PO.
    begin
      Cloudinary::Api.delete_resources(page_ids.drop(1)) if page_ids.length > 1
    rescue => e
      Rails.logger.warn "[PurchaseOrderService] page cleanup failed for #{tag}: #{e.message}"
    end

    { public_id: combined["public_id"], secure_url: combined["secure_url"],
      format: "pdf", bytes: combined["bytes"],
      thumbnail_url: scan_thumbnail_url(page_ids.first) }
  end
  private_class_method :upload_images_as_pdf

  def self.with_tempfile(basename, ext, base64_data)
    tempfile = Tempfile.new([basename, ext], binmode: true)
    tempfile.write(Base64.decode64(base64_data))
    tempfile.flush
    yield tempfile
  ensure
    tempfile&.close!
  end
  private_class_method :with_tempfile

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
