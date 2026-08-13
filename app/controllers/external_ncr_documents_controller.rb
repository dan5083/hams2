# app/controllers/external_ncr_documents_controller.rb
class ExternalNcrDocumentsController < ApplicationController
  before_action :set_external_ncr, only: [:create]
  before_action :set_document,     only: [:destroy, :download]
  before_action :require_ncr_manage_access, only: [:destroy]

  def create
    file = params.dig(:external_ncr_document, :file)

    if file.blank?
      redirect_to @external_ncr, alert: 'Please choose a file to upload.'
      return
    end

    document_type = params.dig(:external_ncr_document, :document_type).presence || 'other'
    note          = params.dig(:external_ncr_document, :note)

    date_for_path = @external_ncr.date.presence || Date.current
    folder_path   = "NCRs/#{date_for_path.year}/#{date_for_path.strftime('%m')}"
    prefix        = "NCR#{@external_ncr.hal_ncr_number || 'DRAFT'}_#{document_type}"

    upload_result = CloudinaryService.upload_file(file, folder_path, filename_prefix: prefix)

    @external_ncr.attach_document!(
      upload_result,
      user: Current.user,
      document_type: document_type,
      note: note
    )

    Rails.logger.info "Attached #{document_type} document to NCR #{@external_ncr.display_name}: #{upload_result[:public_id]}"
    redirect_to @external_ncr, notice: 'Document added.'

  rescue CloudinaryService::CloudinaryError => e
    Rails.logger.error "Failed to upload NCR document: #{e.message}"
    redirect_to @external_ncr, alert: "Upload failed: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    # Upload succeeded but the record didn't save — don't orphan the file.
    begin
      CloudinaryService.delete_file(upload_result[:public_id]) if upload_result
    rescue => cleanup_error
      Rails.logger.error "Failed to clean up orphaned upload: #{cleanup_error.message}"
    end
    redirect_to @external_ncr, alert: "Could not attach document: #{e.record.errors.full_messages.to_sentence}"
  end

  def destroy
    ncr = @document.external_ncr
    filename = @document.filename
    @document.destroy
    redirect_to ncr, notice: "#{filename} removed."
  end

  def download
    url = @document.download_url

    if url
      redirect_to url, allow_other_host: true
    else
      redirect_to @document.external_ncr, alert: 'Unable to generate download link. Please try again.'
    end
  end

  private

  def set_external_ncr
    @external_ncr = ExternalNcr.find(params[:external_ncr_id])
  end

  def set_document
    @document = ExternalNcrDocument.find(params[:id])
  end
end
