# app/services/cloudinary_service.rb
class CloudinaryService
  class CloudinaryError < StandardError; end

  # Generic file upload method
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

    # Get the file extension and preserve it
    file_extension = File.extname(original_name)
    sanitized_name = sanitize_filename(File.basename(original_name, file_extension))
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    # Include file extension in public_id
    public_id = if filename_prefix.present?
                  "#{folder_path}/#{filename_prefix}_#{timestamp}_#{sanitized_name}#{file_extension}"
                else
                  "#{folder_path}/#{timestamp}_#{sanitized_name}#{file_extension}"
                end

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
      resource_type: (original_name.match?(/\.(pdf|doc|docx)$/i) ? 'raw' : 'auto'),
      overwrite: true,
      unique_filename: false,
      use_filename: false
    )

    Rails.logger.info "Successfully uploaded file to Cloudinary: #{result['public_id']}"

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

 # Replace the generate_download_url method in app/services/cloudinary_service.rb
def self.generate_download_url(public_id, options = {})
  raise ArgumentError, "Public ID is required" if public_id.blank?

  begin
    # Determine resource type based on file extension
    resource_type = if public_id.match?(/\.(pdf|doc|docx)$/i)
                      'raw'
                    else
                      'image'
                    end

    # Get the resource info to get the direct secure URL
    resource_info = Cloudinary::Api.resource(public_id, resource_type: resource_type)

    # Check if there's already a derived resource with attachment flag
    derived_with_attachment = resource_info['derived']&.find { |d| d['transformation']&.include?('fl_attachment') }

    if derived_with_attachment
      # Use the pre-generated attachment URL
      derived_with_attachment['secure_url']
    else
      # Use the direct secure URL - browsers will typically download PDFs anyway
      resource_info['secure_url']
    end

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

  # Delete file from Cloudinary
  def self.delete_file(public_id, resource_type: 'auto')
    raise ArgumentError, "Public ID is required" if public_id.blank?

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
