# app/services/dropbox_ncr_service.rb
class DropboxNcrService
  class DropboxError < StandardError; end

  def self.client
    token = ENV['DROPBOX_ACCESS_TOKEN']
    raise "DROPBOX_ACCESS_TOKEN environment variable not set" if token.blank?
    @client ||= DropboxApi::Client.new(token)
  end

  def self.upload_document(external_ncr, file_attachment)
    raise ArgumentError, "ExternalNcr is required" unless external_ncr
    raise ArgumentError, "File attachment is required" unless file_attachment

    begin
      # Create folder structure: /NCRs/YYYY/MM/
      folder_path = "/NCRs/#{external_ncr.date.year}/#{external_ncr.date.strftime('%m')}"
      ensure_folder_exists(folder_path)

      # Generate unique filename
      original_name = file_attachment.blob.filename.to_s
      sanitized_name = sanitize_filename(original_name)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "NCR#{external_ncr.hal_ncr_number}_#{timestamp}_#{sanitized_name}"
      full_path = "#{folder_path}/#{filename}"

      # Read file content
      file_content = file_attachment.blob.download

      # Upload to Dropbox
      client.upload(full_path, file_content, mode: :overwrite)

      Rails.logger.info "Successfully uploaded file to Dropbox: #{full_path}"
      full_path

    rescue DropboxApi::Errors::BasicError => e
      Rails.logger.error "Dropbox API error uploading NCR #{external_ncr.hal_ncr_number}: #{e.message}"
      raise DropboxError, "Failed to upload to Dropbox: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error uploading NCR #{external_ncr.hal_ncr_number}: #{e.message}"
      raise DropboxError, "Upload failed: #{e.message}"
    end
  end

  def self.generate_download_link(dropbox_path, expires_at: 4.hours.from_now)
    raise ArgumentError, "Dropbox path is required" if dropbox_path.blank?

    begin
      # Generate a temporary link (valid for 4 hours by default)
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

  def self.delete_document(dropbox_path)
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

  def self.list_ncr_documents(year = Date.current.year, month = nil)
    folder_path = if month
                    "/NCRs/#{year}/#{month.to_s.rjust(2, '0')}"
                  else
                    "/NCRs/#{year}"
                  end

    begin
      entries = client.list_folder(folder_path, recursive: month.nil?)
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

  def self.validate_file_type(content_type, allowed_types = nil)
    allowed_types ||= [
      'application/pdf',
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/tiff',
      'image/tif',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ]

    allowed_types.include?(content_type)
  end

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
end
