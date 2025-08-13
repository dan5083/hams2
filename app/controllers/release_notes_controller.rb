class ReleaseNotesController < ApplicationController
  before_action :set_release_note, only: [:show, :edit, :update, :destroy, :void, :pdf]
  before_action :set_works_order, only: [:new, :create]

  def index
    @release_notes = ReleaseNote.includes(:works_order, :issued_by, :invoice_item)
                                .order(number: :desc)

    # Filter by status
    case params[:status]
    when 'active'
      @release_notes = @release_notes.active
    when 'voided'
      @release_notes = @release_notes.voided
    when 'pending_invoice'
      @release_notes = @release_notes.requires_invoicing
    when 'invoiced'
      @release_notes = @release_notes.joins(:invoice_item)
    end

    # Filter by customer
    if params[:customer_id].present?
      @release_notes = @release_notes.joins(works_order: { customer_order: :customer })
                                    .where(customer_orders: { customer_id: params[:customer_id] })
    end

    # Search by release note number
    if params[:search].present?
      @release_notes = @release_notes.where("number::text ILIKE ?", "%#{params[:search]}%")
    end

    # For the filter dropdown
    @customers = Organization.customers.enabled.order(:name)
  end

  def show
  end

  def new
    @release_note = @works_order.release_notes.build
    @release_note.issued_by = Current.user
    @release_note.date = Date.current
  end

  def create
    @release_note = @works_order.release_notes.build(release_note_params)
    @release_note.issued_by = Current.user

    if @release_note.save
      redirect_to @release_note, notice: 'Release note was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @release_note.update(release_note_params)
      redirect_to @release_note, notice: 'Release note was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @release_note.can_be_deleted?
      @release_note.destroy
      redirect_to release_notes_url, notice: 'Release note was successfully deleted.'
    else
      redirect_to @release_note, alert: 'Cannot delete release note that has been invoiced.'
    end
  end

  def void
    begin
      @release_note.void!
      redirect_to @release_note, notice: 'Release note was successfully voided.'
    rescue StandardError => e
      redirect_to @release_note, alert: e.message
    end
  end

  def pdf
    # Set up data for the PDF template
    @company_name = "Hard Anodising Surface Treatments Ltd"
    @trading_address = "Your Company Address\nCity, County\nPostcode"

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        # If using wicked_pdf
        render pdf: "release_note_#{@release_note.number}",
               layout: false,
               template: 'release_notes/pdf',
               page_size: 'A4',
               margin: {
                 top: 20,
                 bottom: 15,
                 left: 15,
                 right: 15
               }
      end
    end
  end

  def pending_invoice
    @release_notes = ReleaseNote.requires_invoicing
                                .includes(:works_order, :issued_by)
                                .order(number: :desc)

    render :index
  end

  private

  def set_release_note
    @release_note = ReleaseNote.find(params[:id])
  end

  def set_works_order
    @works_order = WorksOrder.find(params[:works_order_id]) if params[:works_order_id]
  end

  def release_note_params
    params.require(:release_note).permit(
      :date,
      :quantity_accepted,
      :quantity_rejected,
      :remarks,
      :no_invoice
    )
  end
end
