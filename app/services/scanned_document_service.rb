# app/services/scanned_document_service.rb
#
# Turn the files on an AI assistant request into PDF bytes — no storage.
# A PDF attachment is passed through as-is; photographed pages are laid out
# one per A4 page and printed through Grover (same Chromium as the release-
# note PDFs), each page redrawn as a compact grayscale "scan" first.
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

  # Each photographed page is redrawn by Chromium as a "scan": scaled to
  # ~150dpi A4 (1240px on the short side), grayscaled, levels stretched so
  # paper -> white and ink -> black, then re-encoded as a JPEG at 65%. Phone
  # photos come in at 1-2MB a page and Chromium would otherwise embed the
  # original bytes in the PDF; this brings a page down to ~150-300KB and
  # improves legibility. Grover waits for body.ready, set once every page
  # has been processed.
  SCAN_MAX_WIDTH   = 1240   # px, short side of A4 at 150dpi
  SCAN_JPEG_QUALITY = 0.65
  SCAN_LEVELS_LOW  = 70     # luminance <= this -> black
  SCAN_LEVELS_HIGH = 200    # luminance >= this -> white

  def self.images_to_pdf(images)
    sources = images.map { |img| "data:#{img[:media_type]};base64,#{img[:data]}" }

    html = <<~HTML
      <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        @page { size: A4; margin: 8mm; }
        html, body { margin: 0; padding: 0; }
        .page { width: 194mm; height: 281mm; display: flex; align-items: center;
                justify-content: center; page-break-after: always; }
        .page:last-child { page-break-after: auto; }
        .page img { max-width: 100%; max-height: 100%; object-fit: contain; }
      </style></head><body>
      <script>
        const SOURCES = #{sources.to_json};
        const MAX_W = #{SCAN_MAX_WIDTH}, Q = #{SCAN_JPEG_QUALITY};
        const LO = #{SCAN_LEVELS_LOW}, HI = #{SCAN_LEVELS_HIGH};

        function load(src) {
          return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
        }

        function scan(img) {
          // Scale so the shorter side is MAX_W (portrait or landscape both fit A4 at ~150dpi).
          const short = Math.min(img.naturalWidth, img.naturalHeight);
          const k = Math.min(1, MAX_W / short);
          const w = Math.round(img.naturalWidth * k), h = Math.round(img.naturalHeight * k);
          const c = document.createElement('canvas'); c.width = w; c.height = h;
          const ctx = c.getContext('2d');
          ctx.drawImage(img, 0, 0, w, h);

          const d = ctx.getImageData(0, 0, w, h), p = d.data, range = HI - LO;
          for (let i = 0; i < p.length; i += 4) {
            // luminance -> levels stretch -> gray
            let v = 0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2];
            v = v <= LO ? 0 : v >= HI ? 255 : ((v - LO) * 255 / range);
            p[i] = p[i + 1] = p[i + 2] = v;
          }
          ctx.putImageData(d, 0, 0);
          return c.toDataURL('image/jpeg', Q);
        }

        (async () => {
          for (const src of SOURCES) {
            const img = await load(src);
            const page = document.createElement('div'); page.className = 'page';
            const out = document.createElement('img'); out.src = scan(img);
            page.appendChild(out); document.body.appendChild(page);
            await load(out.src); // make sure the re-encoded image is decoded before print
          }
          document.body.classList.add('ready');
        })().catch(e => { document.body.textContent = 'scan failed: ' + e; document.body.classList.add('ready'); });
      </script>
      </body></html>
    HTML

    Grover.new(html, format: "A4", print_background: true,
                     prefer_css_page_size: true,
                     wait_until: "domcontentloaded",
                     wait_for_selector: "body.ready").to_pdf
  end
  private_class_method :images_to_pdf
end
