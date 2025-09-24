# app/services/dropbox_service.rb
class DropboxService
  class DropboxError < StandardError; end

  def self.client
    token = ENV['DROPBOX_ACCESS_TOKEN']
    raise "DROPBOX_ACCESS_TOKEN environment variable not set" if token.blank?
    @client ||= DropboxApi::Client.new(token)
  end

  # Generic file upload method
  def self.upload_file(uploaded_file, folder_path, filename_prefix: nil)
    raise ArgumentError, "Uploaded file is required" unless uploaded_file
    raise ArgumentError, "Folder path is required" if folder_path.blank?

    begin
      # Ensure folder exists
      ensure_folder_exists(folder_path)

      # Generate unique filename
      original_name = if uploaded_file.respond_to?(:original_filename)
                        uploaded_file.original_filename
                      else
                        uploaded_file.filename.to_s
                      end

      sanitized_name = sanitize_filename(original_name)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

      filename = if filename_prefix.present?
                   "#{filename_prefix}_#{timestamp}_#{sanitized_name}"
                 else
                   "#{timestamp}_#{sanitized_name}"
                 end

      full_path = "#{folder_path}/#{filename}"

      # Read file content
      file_content = if uploaded_file.respond_to?(:tempfile)
                       uploaded_file.tempfile.read
                     elsif uploaded_file.respond_to?(:read)
                       uploaded_file.read
                     else
                       uploaded_file.blob.download
                     end

      # Upload to Dropbox
      client.upload(full_path, file_content, mode: :overwrite)

      Rails.logger.info "Successfully uploaded file to Dropbox: #{full_path}"

      {
        path: full_path,
        filename: original_name,
        size: file_content.bytesize,
        content_type: uploaded_file.content_type
      }

    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error uploading file: #{e.message}"
      raise DropboxError, "Failed to upload to Dropbox: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error uploading file: #{e.message}"
      raise DropboxError, "Upload failed: #{e.message}"
    end
  end

  # Generate temporary download link (4 hours by default)
  def self.generate_download_link(dropbox_path, expires_at: 4.hours.from_now)
    raise ArgumentError, "Dropbox path is required" if dropbox_path.blank?

    begin
      response = client.get_temporary_link(dropbox_path)
      response.link

    rescue DropboxApi::Errors::NotFoundError
      Rails.logger.error "File not found in Dropbox: #{dropbox_path}"
      raise DropboxError, "Document not found in Dropbox"
    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error generating download link for #{dropbox_path}: #{e.message}"
      raise DropboxError, "Failed to generate download link: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error generating download link for #{dropbox_path}: #{e.message}"
      raise DropboxError, "Download link generation failed: #{e.message}"
    end
  end

  # Delete file from Dropbox
  def self.delete_file(dropbox_path)
    raise ArgumentError, "Dropbox path is required" if dropbox_path.blank?

    begin
      client.delete(dropbox_path)
      Rails.logger.info "Successfully deleted file from Dropbox: #{dropbox_path}"
      true

    rescue DropboxApi::Errors::NotFoundError
      Rails.logger.warn "File not found for deletion in Dropbox: #{dropbox_path}"
      true # Consider it successfully deleted if it doesn't exist
    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error deleting #{dropbox_path}: #{e.message}"
      raise DropboxError, "Failed to delete from Dropbox: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error deleting #{dropbox_path}: #{e.message}"
      raise DropboxError, "Deletion failed: #{e.message}"
    end
  end

  # Get file metadata
  def self.get_file_metadata(dropbox_path)
    raise ArgumentError, "Dropbox path is required" if dropbox_path.blank?

    begin
      metadata = client.get_metadata(dropbox_path)
      {
        name: metadata.name,
        size: metadata.size,
        modified_at: metadata.server_modified,
        content_hash: metadata.content_hash
      }

    rescue DropboxApi::Errors::NotFoundError
      Rails.logger.error "File not found in Dropbox: #{dropbox_path}"
      nil
    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error getting metadata for #{dropbox_path}: #{e.message}"
      nil
    end
  end

  # List files in a folder
  def self.list_files(folder_path, recursive: false)
    begin
      entries = client.list_folder(folder_path, recursive: recursive)
      entries.entries.map do |entry|
        {
          name: entry.name,
          path: entry.path_display,
          size: entry.size,
          modified_at: entry.server_modified
        }
      end

    rescue DropboxApi::Errors::NotFoundError
      Rails.logger.info "Folder not found in Dropbox: #{folder_path}"
      []
    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error listing folder #{folder_path}: #{e.message}"
      []
    end
  end

  # Test connection
  def self.connection_test
    begin
      account_info = client.get_current_account
      {
        success: true,
        account_name: "#{account_info.name.given_name} #{account_info.name.surname}",
        email: account_info.email,
        account_id: account_info.account_id
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end

  private

  def self.ensure_folder_exists(folder_path)
    begin
      client.get_metadata(folder_path)
    rescue DropboxApi::Errors::NotFoundError
      # Folder doesn't exist, create it
      begin
        client.create_folder(folder_path)
        Rails.logger.info "Created Dropbox folder: #{folder_path}"
      rescue DropboxApi::Errors::BasicError => e
        Rails.logger.error "Failed to create Dropbox folder #{folder_path}: #{e.message}"
        raise DropboxError, "Failed to create folder: #{e.message}"
      end
    end
  end

  def self.sanitize_filename(filename)
    # Remove or replace characters that might cause issues
    filename.gsub(/[^a-zA-Z0-9\-_\.]/, '_')
            .gsub(/_{2,}/, '_')
            .gsub(/^_+|_+$/, '')
  end
end
