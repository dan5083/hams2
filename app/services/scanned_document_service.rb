# app/services/scanned_document_service.rb
#
# Turn the files on an AI assistant request into PDF bytes — no storage.
# A PDF attachment is passed through as-is; photographed pages are laid out
# one per A4 page and printed through Grover (already in the stack for the
# release-note PDFs), with a CSS filter doing the grayscale/contrast cleanup
# that Cloudinary used to do for POs.
#
# MUST run in the same assistant run the files were attached in — base64 is
# stripped from AiAssistantRequest#messages once the job finishes.
require "base64"

class ScannedDocumentService
  class NoAttachmentsError < StandardError; end

  # Returns { bytes:, source: "pdf"|"scanned_images", pages: n|nil }
  def self.pdf_from_request(request_id:)
    request = AiAssistantRequest.find(request_id)
    pdfs, images = collect_base64(request)

    if pdfs.empty? && images.empty?
      raise NoAttachmentsError, "No PDF or image attachments found in the request messages."
    end

    if pdfs.any?
      { bytes: Base64.decode64(pdfs.first), source: "pdf", pages: nil }
    else
      { bytes: images_to_pdf(images), source: "scanned_images", pages: images.length }
    end
  end

  # ---------------------------------------------------------------------------

  def self.collect_base64(request)
    pdfs, images = [], []
    request.messages.each do |msg|
      content = msg["content"]
      next unless content.is_a?(Array)
      content.each do |block|
        source = block["source"]
        next unless source&.dig("type") == "base64" && source["data"].present?
        media_type = source["media_type"].to_s
        if media_type == "application/pdf"
          pdfs << source["data"]
        elsif media_type.start_with?("image/")
          images << { data: source["data"], media_type: media_type }
        end
      end
    end
    [pdfs, images]
  end
  private_class_method :collect_base64

  # One image per page, fitted inside the printable area, EXIF orientation
  # honoured by Chromium. Filter: grayscale + contrast lift so a phone photo of
  # a signed sheet prints like a scan.
  def self.images_to_pdf(images)
    pages = images.map do |img|
      %(<div class="page"><img src="data:#{img[:media_type]};base64,#{img[:data]}"></div>)
    end.join

    html = <<~HTML
      <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        @page { size: A4; margin: 8mm; }
        html, body { margin: 0; padding: 0; }
        .page { width: 194mm; height: 281mm; display: flex; align-items: center;
                justify-content: center; page-break-after: always; }
        .page:last-child { page-break-after: auto; }
        img { max-width: 100%; max-height: 100%; object-fit: contain;
              image-orientation: from-image; filter: grayscale(1) contrast(1.25); }
      </style></head><body>#{pages}</body></html>
    HTML

    Grover.new(html, format: "A4", print_background: true,
                     prefer_css_page_size: true, wait_until: "domcontentloaded").to_pdf
  end
  private_class_method :images_to_pdf
end
