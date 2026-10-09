# app/services/anthropic_files.rb
#
# Anthropic Files API: upload a file once, reference it by file_id in every
# subsequent Messages call instead of resending the bytes as base64. The
# assistant jobs re-send the whole conversation on every agentic turn, so
# base64 attachments were being serialised 5-30 times per run — this is what
# was pushing the worker dyno past its memory quota.
#
# Files are retained on Anthropic's side until deleted; they are free to
# store. https://platform.claude.com/docs/en/build-with-claude/files
require "net/http"
require "uri"
require "json"

module AnthropicFiles
  FILES_URL = URI("https://api.anthropic.com/v1/files").freeze
  BETA      = "files-api-2025-04-14".freeze # optional now the API is GA; harmless

  # Raw bytes -> file_id. One multipart POST; nothing is kept locally.
  def self.upload(bytes, filename:, media_type:)
    req = Net::HTTP::Post.new(FILES_URL)
    headers.each { |k, v| req[k] = v }
    req.set_form([["file", bytes, { filename: filename.to_s.presence || "file", content_type: media_type }]],
                 "multipart/form-data")

    res = Net::HTTP.start(FILES_URL.host, FILES_URL.port, use_ssl: true, read_timeout: 120) { |h| h.request(req) }
    raise "Anthropic file upload failed #{res.code}: #{res.body.to_s.first(300)}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body).fetch("id")
  end

  # Fetch a public URL (a Cloudinary secure_url) and upload it. Follows
  # redirects. Returns nil if the URL can't be read — callers decide whether
  # a missing file is fatal.
  def self.upload_from_url(url, filename:, media_type:, limit: 3)
    return nil if url.blank?
    res = Net::HTTP.get_response(URI(url))
    return upload_from_url(res["location"], filename: filename, media_type: media_type, limit: limit - 1) if res.is_a?(Net::HTTPRedirection) && limit > 0
    return nil unless res.is_a?(Net::HTTPSuccess)
    upload(res.body, filename: filename, media_type: media_type)
  rescue => e
    Rails.logger.warn "[AnthropicFiles] could not upload #{url}: #{e.message}"
    nil
  end

  def self.delete(file_id)
    req = Net::HTTP::Delete.new(URI("#{FILES_URL}/#{file_id}"))
    headers.each { |k, v| req[k] = v }
    Net::HTTP.start(FILES_URL.host, FILES_URL.port, use_ssl: true) { |h| h.request(req) }.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.warn "[AnthropicFiles] delete #{file_id} failed: #{e.message}"
    false
  end

  # The Messages API content block for a stored file. PDFs are documents,
  # everything else we accept is an image.
  def self.content_block(file_id, media_type, title: nil)
    if media_type.to_s == "application/pdf"
      { "type" => "document", "source" => { "type" => "file", "file_id" => file_id }, "title" => title.presence }.compact
    else
      { "type" => "image", "source" => { "type" => "file", "file_id" => file_id } }
    end
  end

  def self.headers
    {
      "x-api-key"         => ENV.fetch("ANTHROPIC_API_KEY"),
      "anthropic-version" => "2023-06-01",
      "anthropic-beta"    => BETA
    }
  end
  private_class_method :headers
end
