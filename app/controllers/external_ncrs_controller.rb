# app/controllers/external_ncrs_controller.rb
class ExternalNcrsController < ApplicationController
  before_action :set_external_ncr, only: [:show, :edit, :update, :destroy, :advance_status]
  before_action :set_release_note, only: [:new, :create], if: -> { params[:release_note_id].present? }

  def index
    @external_ncrs = ExternalNcr.includes(:release_note, :customer, :created_by, :respondent)
                                .active
                                .recent

    # Search functionality
    if params[:search].present?
      @external_ncrs = @external_ncrs.search(params[:search])
    end

    # Status filtering
    if params[:status].present? && params[:status] != 'all'
      @external_ncrs = @external_ncrs.by_status(params[:status])
    end

    # Document status filtering
    if params[:document_status].present?
      case params[:document_status]
      when 'with_documents'
        @external_ncrs = @external_ncrs.with_documents
      when 'missing_documents'
        @external_ncrs = @external_ncrs.missing_documents
      end
    end

    @external_ncrs = @external_ncrs.page(params[:page]).per(20)
  end

  def show
    @download_url = @external_ncr.generate_dropbox_download_url if @external_ncr.has_document?
  end

  def new
    if @release_note
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

    # Handle file upload
    if params[:external_ncr][:temp_document].present?
      @external_ncr.temp_document = params[:external_ncr][:temp_document]
    end

    if @external_ncr.save
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully created."
    else
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
    if params[:external_ncr][:temp_document].present? && @external_ncr.can_replace_document?
      if @external_ncr.replace_document!(params[:external_ncr][:temp_document])
        redirect_to @external_ncr, notice: "Document replaced successfully."
        return
      else
        flash.now[:alert] = 'Failed to replace document.'
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
      # Delete document from Dropbox if it exists
      if @external_ncr.has_document?
        begin
          DropboxNcrService.delete_document(@external_ncr.dropbox_file_path)
        rescue => e
          Rails.logger.error "Failed to delete Dropbox document for NCR #{@external_ncr.hal_ncr_number}: #{e.message}"
          # Continue with NCR deletion even if Dropbox deletion fails
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

  # Download document endpoint
  def download_document
    if @external_ncr.has_document?
      download_url = @external_ncr.generate_dropbox_download_url

      if download_url
        redirect_to download_url
      else
        redirect_to @external_ncr, alert: 'Unable to generate download link. Please try again.'
      end
    else
      redirect_to @external_ncr, alert: 'No document available for download.'
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
