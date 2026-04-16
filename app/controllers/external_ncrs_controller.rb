# app/controllers/external_ncrs_controller.rb
class ExternalNcrsController < ApplicationController
  before_action :require_quality_access
  before_action :set_external_ncr, only: [:show, :edit, :update, :destroy, :advance_status, :download_document]

  def index
    @external_ncrs = ExternalNcr.includes(:release_notes, :created_by, :respondent)
                                .recent

    if params[:search].present?
      @external_ncrs = @external_ncrs.search(params[:search])
    end

    @external_ncrs = @external_ncrs.page(params[:page]).per(20)
  end

  def show
  end

  def new
    @external_ncr = ExternalNcr.new

    # If launched from a specific release note, pre-select it
    if params[:release_note_id].present?
      @preselected_release_note = ReleaseNote.find(params[:release_note_id])
    end
  end

  def create
    @external_ncr = ExternalNcr.new(external_ncr_params)

    # Auto-assign creator as respondent
    @external_ncr.created_by = Current.user
    @external_ncr.respondent = Current.user

    # Build release note associations from submitted IDs (UUIDs — do NOT .to_i)
    release_note_ids = Array(params[:external_ncr][:release_note_ids]).reject(&:blank?)
    release_note_ids.each do |rn_id|
      @external_ncr.external_ncr_release_notes.build(release_note_id: rn_id)
    end

    # Handle file upload
    uploaded_file = params[:external_ncr][:temp_document]

    if uploaded_file.present?
      begin
        folder_path = "NCRs/#{@external_ncr.date.year}/#{@external_ncr.date.strftime('%m')}"
        filename_prefix = "NCR#{@external_ncr.hal_ncr_number || 'TEMP'}"

        upload_result = CloudinaryService.upload_file(uploaded_file, folder_path, filename_prefix: filename_prefix)
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
      @external_ncr.errors.add(:temp_document, "is required")
      prepare_form_data
      render :new, status: :unprocessable_entity
      return
    end

    if @external_ncr.save
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully created."
    else
      # Clean up uploaded file on save failure
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
    # No status guard — the update action has granular status checks and the
    # form conditionally hides the release note editor and document-replace
    # input for non-draft NCRs. Content fields remain editable at any status.
  end

  def update
    # Handle document replacement for draft NCRs
    uploaded_file = params[:external_ncr][:temp_document]

    if uploaded_file.present? && @external_ncr.can_replace_document?
      begin
        folder_path = "NCRs/#{@external_ncr.date.year}/#{@external_ncr.date.strftime('%m')}"
        filename_prefix = "NCR#{@external_ncr.hal_ncr_number}"

        upload_result = CloudinaryService.upload_file(uploaded_file, folder_path, filename_prefix: filename_prefix)
        @external_ncr.replace_document!(upload_result)

        Rails.logger.info "Successfully replaced document for NCR #{@external_ncr.hal_ncr_number}"

      rescue CloudinaryService::CloudinaryError => e
        Rails.logger.error "Failed to replace document: #{e.message}"
        redirect_to edit_external_ncr_path(@external_ncr), alert: "Failed to replace document: #{e.message}"
        return
      end
    end

    # Handle release note IDs update (only for draft NCRs)
    if @external_ncr.status == 'draft' && params[:external_ncr][:release_note_ids].present?
      new_ids = Array(params[:external_ncr][:release_note_ids]).reject(&:blank?)
      @external_ncr.release_note_ids = new_ids
    end

    if @external_ncr.update(external_ncr_params)
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @external_ncr.status == 'draft'
      if @external_ncr.cloudinary_public_id.present?
        begin
          CloudinaryService.delete_file(@external_ncr.cloudinary_public_id)
        rescue => e
          Rails.logger.error "Failed to delete Cloudinary document for NCR #{@external_ncr.hal_ncr_number}: #{e.message}"
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
        'Please complete corrective action and preventive action fields.'
      else
        'Cannot advance NCR status.'
      end

      redirect_to @external_ncr, alert: error_message
    end
  end

  # AJAX endpoint for release note search
  def search_release_notes
    search_term = params[:q].to_s.strip

    if search_term.blank?
      release_notes = ReleaseNote.includes(works_order: [:customer_order, :part])
                                 .where(voided: false)
                                 .order(number: :desc)
                                 .limit(20)
    else
      release_notes = ReleaseNote.includes(works_order: [:customer_order, :part])
                                 .joins(works_order: :customer_order)
                                 .joins('LEFT JOIN organizations ON customer_orders.customer_id = organizations.id')
                                 .where(voided: false)
                                 .where(
                                   "CAST(release_notes.number AS TEXT) ILIKE ? OR " \
                                   "CAST(works_orders.number AS TEXT) ILIKE ? OR " \
                                   "organizations.name ILIKE ? OR " \
                                   "works_orders.part_number ILIKE ?",
                                   "%#{search_term}%", "%#{search_term}%", "%#{search_term}%", "%#{search_term}%"
                                 )
                                 .order(number: :desc)
                                 .limit(50)
    end

    results = release_notes.map do |rn|
      {
        id: rn.id,
        number: rn.number,
        display_text: "RN#{rn.number} - #{rn.works_order.customer_name} - #{rn.works_order.part_number}-#{rn.works_order.part_issue}",
        customer_name: rn.works_order.customer_name,
        part_number: rn.works_order.part_number,
        part_issue: rn.works_order.part_issue,
        works_order_number: rn.works_order.display_name
      }
    end

    render json: results
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
    end
  end

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

  def external_ncr_params
    params.require(:external_ncr).permit(
      :date,
      :concession_number, :customer_ncr_number, :estimated_cost,
      :reject_quantity,
      :description_of_non_conformance, :containment_action,
      :root_cause_analysis, :corrective_action, :preventive_action
      # Note: release_note_ids and temp_document are handled separately
    )
  end

  def prepare_form_data
    if params[:release_note_id].present?
      @preselected_release_note = ReleaseNote.find_by(id: params[:release_note_id])
    end
  end
end
