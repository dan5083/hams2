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
