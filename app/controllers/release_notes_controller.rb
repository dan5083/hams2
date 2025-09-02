# app/controllers/release_notes_controller.rb
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

    # Handle thickness measurements if present
    if thickness_measurements_provided?
      process_thickness_measurements
    end

    if @release_note.save
      redirect_to @release_note, notice: 'Release note was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # Handle thickness measurements if present
    if thickness_measurements_provided?
      process_thickness_measurements
    end

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
    # Set up data for the PDF template - customer delivery documentation
    @company_name = "Hard Anodising Surface Treatments Ltd"
    @trading_address = "Firs Industrial Estate, Rickets Close\nKidderminster, DY11 7QN"

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        pdf = Grover.new(
          render_to_string(
            template: 'release_notes/pdf',
            layout: false,
            locals: { release_note: @release_note, company_name: @company_name, trading_address: @trading_address }
          ),
          format: 'A4',
          margin: { top: '1cm', bottom: '1cm', left: '1cm', right: '1cm' },
          print_background: true,
          prefer_css_page_size: true
        ).to_pdf

        send_data pdf,
                  filename: "delivery_note_#{@release_note.number}.pdf",
                  type: 'application/pdf',
                  disposition: 'inline'
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
      :no_invoice,
      :measured_thicknesses
    )
  end

  def thickness_measurements_provided?
    # Check if individual thickness fields were provided
    thickness_field_names = ReleaseNote::MEASURABLE_PROCESS_TYPES.map { |type| "thickness_#{type}" }
    thickness_field_names.any? { |field| params[field].present? }
  end

  def process_thickness_measurements
    # Process individual thickness fields and convert to JSONB array
    Rails.logger.info "Processing thickness measurements for release note"

    required_types = @release_note.get_required_thickness_types
    Rails.logger.info "Required thickness types: #{required_types}"

    # Initialize the measurements array if needed
    @release_note.measured_thicknesses ||= Array.new(ReleaseNote::THICKNESS_POSITIONS.size)

    # Process each required thickness type
    required_types.each do |process_type|
      field_name = "thickness_#{process_type}"
      field_value = params[field_name]

      Rails.logger.info "Processing #{field_name}: #{field_value}"

      if field_value.present?
        success = @release_note.set_thickness(process_type, field_value)
        Rails.logger.info "Set thickness for #{process_type}: #{success}"

        unless success
          @release_note.errors.add(:measured_thicknesses,
            "Invalid thickness value for #{process_type.humanize.gsub('_', ' ').titleize}")
        end
      elsif @release_note.requires_thickness_measurements?
        # If thickness is required but not provided, the model validation will catch this
        Rails.logger.warn "Missing required thickness for #{process_type}"
      end
    end

    Rails.logger.info "Final measured_thicknesses: #{@release_note.measured_thicknesses}"
  end
end
