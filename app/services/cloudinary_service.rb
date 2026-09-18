# app/services/cloudinary_service.rb
class CloudinaryService
  class CloudinaryError < StandardError; end

# Update the upload_file method in CloudinaryService
def self.upload_file(uploaded_file, folder_path, filename_prefix: nil, resource_type: 'auto')
  raise ArgumentError, "Uploaded file is required" unless uploaded_file
  raise ArgumentError, "Folder path is required" if folder_path.blank?

  begin
    # Generate unique public_id
    original_name = if uploaded_file.respond_to?(:original_filename)
                      uploaded_file.original_filename
                    else
                      uploaded_file.filename.to_s
                    end

    # Get the file extension but DON'T include it in public_id for raw files
    file_extension = File.extname(original_name)
    sanitized_name = sanitize_filename(File.basename(original_name, file_extension))
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    # Determine resource type. PDFs go up as IMAGE resources: Cloudinary can
    # then render any page of them on the fly (pg_N,w_...,f_jpg), which is
    # what the drawing thumbnails and preview modal on parts/works orders
    # use. Raw is for genuinely opaque documents (Word, DWG, DXF ...) that
    # Cloudinary can't rasterise - nothing is lost storing them that way.
    # 'auto' lets Cloudinary classify images/video itself.
    detected_resource_type = if original_name.match?(/\.pdf$/i)
                               'image'
                             elsif original_name.match?(/\.(doc|docx|dwg|dxf|step|stp|iges|igs)$/i)
                               'raw'
                             else
                               'auto'
                             end

    # DON'T include file extension in public_id for raw files
    public_id = if filename_prefix.present?
                  "#{folder_path}/#{filename_prefix}_#{timestamp}_#{sanitized_name}"
                else
                  "#{folder_path}/#{timestamp}_#{sanitized_name}"
                end

    Rails.logger.info "About to upload with public_id: #{public_id}"
    # Get file content
    file_content = if uploaded_file.respond_to?(:tempfile)
                     uploaded_file.tempfile
                   elsif uploaded_file.respond_to?(:path)
                     uploaded_file.path
                   else
                     uploaded_file
                   end

    # Upload to Cloudinary
    result = Cloudinary::Uploader.upload(
      file_content,
      public_id: public_id,
      resource_type: detected_resource_type,
      type: 'upload',
      access_mode: 'public',
      overwrite: true,
      unique_filename: false,
      use_filename: false
    )

    Rails.logger.info "Successfully uploaded file to Cloudinary: #{result['public_id']}"
    Rails.logger.info "Cloudinary upload result: #{result.inspect}"
    Rails.logger.info "Cloudinary resource_type used: #{detected_resource_type}"
    Rails.logger.info "Cloudinary secure_url: #{result['secure_url']}"
    Rails.logger.info "Cloudinary url: #{result['url']}"

    {
      public_id: result['public_id'],
      secure_url: result['secure_url'],
      url: result['url'],
      filename: original_name,
      size: result['bytes'],
      content_type: uploaded_file.content_type,
      format: result['format'],
      version: result['version']
    }

  rescue Cloudinary::Api::Error => e
    Rails.logger.error "Cloudinary API error uploading file: #{e.message}"
    raise CloudinaryError, "Failed to upload to Cloudinary: #{e.message}"
  rescue => e
    Rails.logger.error "Unexpected error uploading file: #{e.message}"
    raise CloudinaryError, "Upload failed: #{e.message}"
  end
end

  # Which Cloudinary resource type an asset lives under, read off the
  # delivery URL we stored at upload time (".../image/upload/...",
  # ".../raw/upload/..."). Guessing from the filename is how PDFs ended up
  # raw in the first place, and how delete_file was sent 'auto' (which
  # destroy rejects) - the URL is the one thing that is always right.
  def self.resource_type_for_url(url)
    case url.to_s
    when %r{/raw/upload/}   then 'raw'
    when %r{/video/upload/} then 'video'
    else 'image'
    end
  end

  # File format (delivery extension) from a stored URL, e.g. "pdf".
  def self.format_for_url(url)
    ext = File.extname(URI.parse(url.to_s).path.to_s).delete('.').downcase
    ext.presence
  rescue URI::InvalidURIError
    nil
  end

  # Download URL. Pass the asset's stored `url:` so resource type and format
  # come from what was actually uploaded; without it we fall back to the
  # legacy name-based guess (raw for a public_id ending .pdf/.doc/.docx).
  def self.generate_download_url(public_id, options = {})
    raise ArgumentError, "Public ID is required" if public_id.blank?

    begin
      stored_url    = options.delete(:url)
      resource_type = options.delete(:resource_type) ||
                      (stored_url ? resource_type_for_url(stored_url) : (public_id.match?(/\.(pdf|doc|docx)$/i) ? 'raw' : 'image'))
      format        = options.delete(:format) || (stored_url ? format_for_url(stored_url) : nil)

      cloud_name = Cloudinary.config.cloud_name

      url = if resource_type == 'raw'
        # Raw assets: plain secure URL, no transformations (the public_id
        # already carries the extension for raw uploads).
        "https://res.cloudinary.com/#{cloud_name}/raw/upload/#{public_id}"
      else
        # Image/video assets: fl_attachment forces a download; the format
        # keeps the original extension (a PDF stored as an image resource
        # has no extension in its public_id, so it must be passed here).
        Cloudinary::Utils.cloudinary_url(
          public_id,
          {
            resource_type: resource_type,
            format: format,
            secure: true,
            flags: 'attachment',
            type: 'upload'
          }.compact.merge(options)
        )
      end

      Rails.logger.info "Generated Cloudinary download URL for #{public_id}: #{url}"
      url

    rescue => e
      Rails.logger.error "Error generating Cloudinary download URL for #{public_id}: #{e.message}"
      nil
    end
  end

  # Generate view URL (for displaying in browser)
  def self.generate_view_url(public_id, options = {})
    raise ArgumentError, "Public ID is required" if public_id.blank?

    begin
      Cloudinary::Utils.cloudinary_url(
        public_id,
        {
          secure: true
        }.merge(options)
      )
    rescue => e
      Rails.logger.error "Error generating Cloudinary view URL for #{public_id}: #{e.message}"
      nil
    end
  end

  # Delete file from Cloudinary. destroy() needs a concrete resource type
  # ('auto' is upload-only and comes back "not found"), so pass either
  # resource_type: or the asset's stored url: and it is derived from that.
  def self.delete_file(public_id, resource_type: nil, url: nil)
    raise ArgumentError, "Public ID is required" if public_id.blank?

    resource_type ||= url ? resource_type_for_url(url) : (public_id.match?(/\.(pdf|doc|docx)$/i) ? 'raw' : 'image')

    begin
      result = Cloudinary::Uploader.destroy(public_id, resource_type: resource_type)

      if result['result'] == 'ok'
        Rails.logger.info "Successfully deleted file from Cloudinary: #{public_id}"
        true
      else
        Rails.logger.warn "File not found or already deleted in Cloudinary: #{public_id}"
        true # Consider it successfully deleted if it doesn't exist
      end

    rescue Cloudinary::Api::Error => e
      Rails.logger.error "Cloudinary API error deleting #{public_id}: #{e.message}"
      raise CloudinaryError, "Failed to delete from Cloudinary: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error deleting #{public_id}: #{e.message}"
      raise CloudinaryError, "Deletion failed: #{e.message}"
    end
  end

  # Get file metadata
  def self.get_file_metadata(public_id, resource_type: 'auto')
    raise ArgumentError, "Public ID is required" if public_id.blank?

    begin
      result = Cloudinary::Api.resource(public_id, resource_type: resource_type)
      {
        public_id: result['public_id'],
        format: result['format'],
        size: result['bytes'],
        width: result['width'],
        height: result['height'],
        created_at: result['created_at'],
        secure_url: result['secure_url']
      }

    rescue Cloudinary::Api::NotFound
      Rails.logger.error "File not found in Cloudinary: #{public_id}"
      nil
    rescue Cloudinary::Api::Error => e
      Rails.logger.error "Cloudinary API error getting metadata for #{public_id}: #{e.message}"
      nil
    end
  end

  # List files in a folder
  def self.list_files(folder_prefix, resource_type: 'auto', max_results: 100)
    begin
      result = Cloudinary::Api.resources(
        type: 'upload',
        resource_type: resource_type,
        prefix: folder_prefix,
        max_results: max_results
      )

      result['resources'].map do |resource|
        {
          public_id: resource['public_id'],
          format: resource['format'],
          size: resource['bytes'],
          created_at: resource['created_at'],
          secure_url: resource['secure_url']
        }
      end

    rescue Cloudinary::Api::Error => e
      Rails.logger.error "Cloudinary API error listing files with prefix #{folder_prefix}: #{e.message}"
      []
    end
  end

  # Test connection
  def self.connection_test
    begin
      # Try to get account usage info
      result = Cloudinary::Api.usage
      {
        success: true,
        cloud_name: Cloudinary.config.cloud_name,
        plan: result['plan'],
        credits: result['credits'],
        objects: result['objects'],
        bandwidth: result['bandwidth']
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end

  private

  def self.sanitize_filename(filename)
    # Remove or replace characters that might cause issues in Cloudinary public_ids
    filename.gsub(/[^a-zA-Z0-9\-_]/, '_')
            .gsub(/_{2,}/, '_')
            .gsub(/^_+|_+$/, '')
  end
end
