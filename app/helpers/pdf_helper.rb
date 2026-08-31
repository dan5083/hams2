# app/helpers/pdf_helper.rb
#
# PDF documents rendered through Grover are handed to headless Chromium as a
# raw HTML string, so a normal image_tag asset path means Chromium has to make
# an HTTP request back to the app to fetch the logo — which is slow (adds an
# asset round-trip to every render) and fragile (it silently fails when the
# relative path can't be resolved, which is why the compiled collection pack
# rendered without a logo).
#
# Instead the logo is embedded as a base64 data URI, read once from the asset
# source and memoised for the life of the process. The document is then fully
# self-contained: no network requests during the Chromium render at all, which
# also makes wait_until: 'domcontentloaded' safe in the Grover calls.
module PdfHelper
  LOGO_ASSET = Rails.root.join("app/assets/images/logo-with-company-name.png")

  # data:image/png;base64,... for the company logo, or nil if the asset is
  # missing (the <img> then simply renders nothing rather than a broken icon).
  def pdf_logo_data_uri
    PdfHelper.logo_data_uri
  end

  def self.logo_data_uri
    return @logo_data_uri if defined?(@logo_data_uri)

    @logo_data_uri =
      if File.exist?(LOGO_ASSET)
        "data:image/png;base64,#{Base64.strict_encode64(File.binread(LOGO_ASSET))}"
      else
        Rails.logger.error "PdfHelper: logo asset missing at #{LOGO_ASSET}"
        nil
      end
  end
end
