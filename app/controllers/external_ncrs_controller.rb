# app/controllers/external_ncrs_controller.rb
class ExternalNcrsController < ApplicationController
  before_action :set_external_ncr, only: [:show, :edit, :update, :destroy, :advance_status, :download_document]
  before_action :set_release_note, only: [:new, :create], if: -> { params[:release_note_id].present? }

  def index
    @external_ncrs = ExternalNcr.includes(:release_note, :customer, :created_by, :respondent)
                                .recent  # Removed .active scope

    # Search functionality (keep this)
    if params[:search].present?
      @external_ncrs = @external_ncrs.search(params[:search])
    end

    @external_ncrs = @external_ncrs.page(params[:page]).per(20)
  end

  def show
    # @download_url = @external_ncr.generate_cloudinary_download_url if @external_ncr.has_document? # Remove this line
  end

  def new
    if params[:release_note_id].present?
      @release_note = ReleaseNote.find(params[:release_note_id])
      @external_ncr = @release_note.external_ncrs.build
    else
      @external_ncr = ExternalNcr.new
      @release_notes = ReleaseNote.includes(works_order: [:customer_order, :part])
                                  .where(voided: false)
                                  .order(number: :desc)
                                  .limit(100)
    end
  end

  def create
    if @release_note
      @external_ncr = @release_note.external_ncrs.build(external_ncr_params)
    else
      @external_ncr = ExternalNcr.new(external_ncr_params)
    end

    # Auto-assign creator as respondent
    @external_ncr.created_by = Current.user
    @external_ncr.respondent = Current.user

    # Handle file upload first, then save the NCR
    uploaded_file = params[:external_ncr][:temp_document]

    if uploaded_file.present?
      begin
        # Upload to Cloudinary
        folder_path = "NCRs/#{@external_ncr.date.year}/#{@external_ncr.date.strftime('%m')}"
        filename_prefix = "NCR#{@external_ncr.hal_ncr_number || 'TEMP'}"

        upload_result = CloudinaryService.upload_file(uploaded_file, folder_path, filename_prefix: filename_prefix)

        # Store document metadata
        @external_ncr.store_document_metadata(upload_result)

        Rails.logger.info "Successfully uploaded document for NCR: #{upload_result[:public_id]}"

      rescue CloudinaryService::CloudinaryError => e
        Rails.logger.error "Failed to upload document: #{e.message}"
        @external_ncr.errors.add(:temp_document, "could not be uploaded: #{e.message}")
        prepare_form_data
        render :new, status: :unprocessable_entity
        return
      end
    elsif @external_ncr.new_record?
      # Require document for new NCRs
      @external_ncr.errors.add(:temp_document, "is required")
      prepare_form_data
      render :new, status: :unprocessable_entity
      return
    end

    if @external_ncr.save
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully created."
    else
      # If save failed and we uploaded a file, clean up
      if @external_ncr.cloudinary_public_id.present?
        begin
          CloudinaryService.delete_file(@external_ncr.cloudinary_public_id)
        rescue => e
          Rails.logger.error "Failed to cleanup uploaded file: #{e.message}"
        end
      end

      prepare_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Only allow editing of draft NCRs for document replacement
    if @external_ncr.status != 'draft' && params[:replace_document].blank?
      redirect_to @external_ncr, alert: 'Only draft NCRs can be fully edited.'
      return
    end
  end

  def update
    # Handle document replacement for draft NCRs
    uploaded_file = params[:external_ncr][:temp_document]

    if uploaded_file.present? && @external_ncr.can_replace_document?
      begin
        # Upload new file to Cloudinary
        folder_path = "NCRs/#{@external_ncr.date.year}/#{@external_ncr.date.strftime('%m')}"
        filename_prefix = "NCR#{@external_ncr.hal_ncr_number}"

        upload_result = CloudinaryService.upload_file(uploaded_file, folder_path, filename_prefix: filename_prefix)

        # Replace the document
        @external_ncr.replace_document!(upload_result)

        Rails.logger.info "Successfully replaced document for NCR #{@external_ncr.hal_ncr_number}"

      rescue CloudinaryService::CloudinaryError => e
        Rails.logger.error "Failed to replace document: #{e.message}"
        redirect_to edit_external_ncr_path(@external_ncr), alert: "Failed to replace document: #{e.message}"
        return
      end
    end

    # Regular update
    if @external_ncr.update(external_ncr_params)
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @external_ncr.status == 'draft'
      # Delete document from Cloudinary if it exists
      if @external_ncr.cloudinary_public_id.present?
        begin
          CloudinaryService.delete_file(@external_ncr.cloudinary_public_id)
        rescue => e
          Rails.logger.error "Failed to delete Cloudinary document for NCR #{@external_ncr.hal_ncr_number}: #{e.message}"
          # Continue with NCR deletion even if Cloudinary deletion fails
        end
      end

      ncr_name = @external_ncr.display_name
      @external_ncr.destroy
      redirect_to external_ncrs_url, notice: "External NCR #{ncr_name} was successfully deleted."
    else
      redirect_to @external_ncr, alert: 'Cannot delete NCR that is not in draft status.'
    end
  end

  def advance_status
    if @external_ncr.advance_status!
      redirect_to @external_ncr, notice: "NCR status advanced to #{@external_ncr.status.humanize}."
    else
      error_message = case @external_ncr.status
      when 'draft'
        if !@external_ncr.description_of_non_conformance.present?
          'Please add a description of non-conformance before advancing.'
        elsif !@external_ncr.has_document?
          'Please upload the incoming NCR document before advancing.'
        else
          'Cannot advance NCR status. Please complete required fields.'
        end
      when 'in_progress'
        'Please complete containment/corrective action and preventive action fields.'
      else
        'Cannot advance NCR status.'
      end

      redirect_to @external_ncr, alert: error_message
    end
  end

  # AJAX endpoint for release note details
  def release_note_details
    release_note = ReleaseNote.find(params[:release_note_id])
    render json: {
      customer_name: release_note.works_order.customer_name,
      part_number: release_note.works_order.part_number,
      part_issue: release_note.works_order.part_issue,
      part_description: release_note.works_order.part_description,
      works_order_number: release_note.works_order.display_name,
      customer_po_number: release_note.works_order.customer_order.number,
      quantity_accepted: release_note.quantity_accepted,
      quantity_rejected: release_note.quantity_rejected,
      batch_quantity: release_note.quantity_accepted + release_note.quantity_rejected
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Release note not found' }, status: :not_found
  end

def download_document
  if @external_ncr.has_document?
    begin
      Rails.logger.info "Starting download for NCR #{@external_ncr.hal_ncr_number}"

      # Generate a signed URL with attachment flag for download
      download_url = CloudinaryService.generate_download_url(@external_ncr.cloudinary_public_id)

      if download_url
        Rails.logger.info "Generated download URL, redirecting to Cloudinary"
        redirect_to download_url, allow_other_host: true
      else
        Rails.logger.error "Failed to generate download URL"
        redirect_to @external_ncr, alert: 'Unable to generate download link. Please try again.'
      end

    rescue => e
      Rails.logger.error "Download error: #{e.class} - #{e.message}"
      redirect_to @external_ncr, alert: "Download failed: #{e.message}"
    end
  else
    redirect_to @external_ncr, alert: 'No document available for download.'
  end
end

def response_pdf
  @external_ncr = ExternalNcr.find(params[:id])

  respond_to do |format|
    format.html { render layout: false }
    format.pdf do
      begin
        Rails.logger.info "About to create PDF using exact Release Notes pattern"

        # Copy the exact pattern from Release Notes, including the begin/rescue structure
        pdf = Grover.new(
          render_to_string(
            template: 'external_ncrs/response',
            layout: false
          ),
          format: 'A4',
          margin: { top: '1cm', bottom: '1cm', left: '1cm', right: '1cm' },
          print_background: true,
          prefer_css_page_size: true
        ).to_pdf

        Rails.logger.info "PDF generated successfully"

        send_data pdf,
                  filename: "NCR_Response_#{@external_ncr.hal_ncr_number}.pdf",
                  type: 'application/pdf',
                  disposition: 'inline'

      rescue => e
        Rails.logger.error "PDF generation failed: #{e.class} - #{e.message}"

        # Instead of returning an error, let's try falling back to a simpler approach
        Rails.logger.info "Attempting fallback with minimal options"

        begin
          simple_pdf = Grover.new(render_to_string(template: 'external_ncrs/response', layout: false)).to_pdf
          send_data simple_pdf,
                    filename: "NCR_Response_#{@external_ncr.hal_ncr_number}.pdf",
                    type: 'application/pdf',
                    disposition: 'inline'
        rescue => fallback_error
          Rails.logger.error "Fallback also failed: #{fallback_error.message}"
          render plain: "PDF generation failed: #{e.message}", status: 500, content_type: 'text/plain'
        end
      end
    end
  end
end

  # Reassign respondent (for managers/admins)
  def reassign_respondent
    new_respondent = User.find(params[:respondent_id])

    if @external_ncr.update(respondent: new_respondent)
      redirect_to @external_ncr, notice: "NCR reassigned to #{new_respondent.full_name}."
    else
      redirect_to @external_ncr, alert: 'Failed to reassign NCR.'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to @external_ncr, alert: 'User not found.'
  end

  private

  def set_external_ncr
    @external_ncr = ExternalNcr.find(params[:id])
  end

  def set_release_note
    @release_note = ReleaseNote.find(params[:release_note_id])
  end

  def external_ncr_params
    params.require(:external_ncr).permit(
      :release_note_id, :date,
      :concession_number, :customer_ncr_number, :estimated_cost,
      :reject_quantity,
      :description_of_non_conformance, :investigation_root_cause_analysis,
      :root_cause_identified, :containment_corrective_action, :preventive_action
      # Note: temp_document is handled separately
    )
  end

  def prepare_form_data
    if @release_note
      # Release note is already set from nested route
    elsif @external_ncr.release_note.present?
      @release_note = @external_ncr.release_note
    else
      @release_notes = ReleaseNote.includes(works_order: [:customer_order, :part])
                                  .where(voided: false)
                                  .order(number: :desc)
                                  .limit(100)
    end
  end
end
