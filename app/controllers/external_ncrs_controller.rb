# app/controllers/external_ncrs_controller.rb
class ExternalNcrsController < ApplicationController
  before_action :set_external_ncr, only: [:show, :edit, :update, :destroy, :advance_status]
  before_action :set_release_note, only: [:new, :create], if: -> { params[:release_note_id].present? }

  def index
    @external_ncrs = ExternalNcr.includes(:release_note, :customer, :created_by, :assigned_to)
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

    @external_ncrs = @external_ncrs.page(params[:page]).per(20)
  end

  def show
  end

  def new
    if @release_note
      @external_ncr = @release_note.external_ncrs.build
    else
      @external_ncr = ExternalNcr.new
      @release_notes = ReleaseNote.active.includes(:works_order).order(number: :desc).limit(100)
    end

    @assignable_users = User.where(enabled: true).order(:full_name)
  end

  def create
    if @release_note
      @external_ncr = @release_note.external_ncrs.build(external_ncr_params)
    else
      @external_ncr = ExternalNcr.new(external_ncr_params)
    end

    @external_ncr.created_by = Current.user

    if @external_ncr.save
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully created."
    else
      prepare_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @assignable_users = User.where(enabled: true).order(:full_name)
  end

  def update
    if @external_ncr.update(external_ncr_params)
      redirect_to @external_ncr, notice: "External NCR #{@external_ncr.display_name} was successfully updated."
    else
      @assignable_users = User.where(enabled: true).order(:full_name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @external_ncr.status == 'draft'
      @external_ncr.destroy
      redirect_to external_ncrs_url, notice: "External NCR #{@external_ncr.display_name} was successfully deleted."
    else
      redirect_to @external_ncr, alert: 'Cannot delete NCR that is not in draft status.'
    end
  end

  def advance_status
    if @external_ncr.advance_status!
      redirect_to @external_ncr, notice: "NCR status advanced to #{@external_ncr.status.humanize}."
    else
      redirect_to @external_ncr, alert: 'Cannot advance NCR status. Please complete required fields first.'
    end
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
      :release_note_id, :date, :assigned_to_id,
      :advice_number, :concession_number, :customer_po_number, :customer_ncr_number,
      :batch_quantity, :reject_quantity,
      :description_of_non_conformance, :investigation_root_cause_analysis,
      :root_cause_identified, :containment_corrective_action, :preventive_action
    )
  end

  def prepare_form_data
    if params[:release_note_id].present?
      @release_note = ReleaseNote.find(params[:release_note_id])
    elsif @external_ncr.release_note.present?
      @release_note = @external_ncr.release_note
    else
      @release_notes = ReleaseNote.active.includes(:works_order).order(number: :desc).limit(100)
    end
    @assignable_users = User.where(enabled: true).order(:full_name)
  end
end
