# app/services/scanned_document_service.rb
#
# Turn the files on an AI assistant request into PDF bytes for the Xero
# attachment. The request holds "hams_file" references (AssistantAttachments);
# the bytes are in Cloudinary. A PDF attachment is fetched as-is; photographed
# pages are combined into one PDF by Cloudinary's `multi` with the same
# cleanup transformation PurchaseOrderService uses for photographed POs
# (EXIF deskew, ≤1400px, grayscale, improve, contrast, sharpen, eco quality
# — ~150-300KB a page instead of the 1-2MB phone original).
#
# Nothing is stored in HAMS. The combined PDF is a Cloudinary asset tagged
# poc_<request_id>; it is deleted again once the bytes are in hand.
#
# Previously this rendered the pages through headless Chromium (Grover) on
# the worker dyno — hundreds of MB per run on a 512MB dyno. Cloudinary does
# the same work now and the worker only ever holds the finished PDF.
require "net/http"
require "uri"

class ScannedDocumentService
  class NoAttachmentsError < StandardError; end

  # Returns { bytes:, source: "pdf"|"scanned_images", pages: n|nil }
  def self.pdf_from_request(request_id:)
    request = AiAssistantRequest.find(request_id)
    pdfs    = request.pdf_attachments
    images  = request.image_attachments

    if pdfs.empty? && images.empty?
      raise NoAttachmentsError, "No PDF or image attachments found in the request messages."
    end

    if pdfs.any?
      { bytes: fetch(pdfs.first["secure_url"]), source: "pdf", pages: nil }
    else
      { bytes: images_to_pdf(images, request_id), source: "scanned_images", pages: images.length }
    end
  end

  # ---------------------------------------------------------------------------

  def self.images_to_pdf(images, request_id)
    tag      = "poc_#{request_id}_#{SecureRandom.hex(4)}"
    page_ids = images.map { |i| i["public_id"] }
    Cloudinary::Uploader.add_tag(tag, page_ids, resource_type: "image")

    combined = Cloudinary::Uploader.multi(
      tag,
      format: "pdf",
      transformation: PurchaseOrderService::IMAGE_CLEANUP_TRANSFORMATION.map(&:dup)
    )

    fetch(combined["secure_url"])
  ensure
    # The multi asset is scratch; the page originals stay with the request.
    # Both best-effort — a tidy-up failure must not lose the PoC.
    begin
      Cloudinary::Uploader.remove_tag(tag, page_ids, resource_type: "image") if page_ids
      Cloudinary::Api.delete_resources([combined["public_id"]], resource_type: "image", type: "multi") if combined
    rescue => e
      Rails.logger.warn "[ScannedDocumentService] cleanup failed for #{tag}: #{e.message}"
    end
  end
  private_class_method :images_to_pdf

  def self.fetch(url, limit = 3)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.get(uri.request_uri) }
    return fetch(res["location"], limit - 1) if res.is_a?(Net::HTTPRedirection) && limit > 0
    raise "Cloudinary fetch failed #{res.code} for #{url}" unless res.is_a?(Net::HTTPSuccess)
    res.body
  end
  private_class_method :fetch
end
