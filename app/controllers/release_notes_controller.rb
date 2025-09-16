# app/controllers/release_notes_controller.rb - Updated to allow post-invoice editing
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
    # NEW: Allow editing for all non-voided release notes (including invoiced ones)
    unless @release_note.can_be_edited?
      redirect_to @release_note, alert: 'Cannot edit voided release notes.'
      return
    end

    # Store original quantities for comparison (used in form warnings)
    @original_quantity_accepted = @release_note.quantity_accepted
    @original_quantity_rejected = @release_note.quantity_rejected
  end

  def update
    # NEW: Allow editing for all non-voided release notes (including invoiced ones)
    unless @release_note.can_be_edited?
      redirect_to @release_note, alert: 'Cannot edit voided release notes.'
      return
    end

    # Handle thickness measurements if present
    if thickness_measurements_provided?
      process_thickness_measurements
    end

    # Store whether this release note was invoiced before update for messaging
    was_invoiced = @release_note.invoiced?

    if @release_note.update(release_note_params)
      success_message = 'Release note was successfully updated.'

      # Add warning if quantities were changed on an invoiced release note
      if was_invoiced && (@release_note.quantity_accepted_previously_changed? || @release_note.quantity_rejected_previously_changed?)
        success_message += ' Note: This release note has already been invoiced - the invoice amounts will not be affected by quantity changes.'
      end

      redirect_to @release_note, notice: success_message
    else
      # Store original quantities again for form warnings on re-render
      @original_quantity_accepted = @release_note.quantity_accepted_was
      @original_quantity_rejected = @release_note.quantity_rejected_was
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
    # Check if measurements were provided via JSON (from new form structure)
    params[:release_note][:measured_thicknesses].present? ||
    # Check if individual thickness fields were provided (legacy support)
    params.keys.any? { |key| key.to_s.start_with?('thickness_measurement_') }
  end

  def process_thickness_measurements
    Rails.logger.info "Processing thickness measurements for release note"

    # First, try to process JSON data from the new form structure
    if release_note_params[:measured_thicknesses].present?
      begin
        json_data = JSON.parse(release_note_params[:measured_thicknesses])
        if json_data.is_a?(Hash) && json_data['measurements'].is_a?(Array)
          Rails.logger.info "Found JSON thickness data with #{json_data['measurements'].length} measurements"
          @release_note.measured_thicknesses = json_data
          return
        end
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse JSON thickness data: #{e.message}"
        # Fall through to individual field processing
      end
    end

    # Fall back to processing individual thickness measurement fields (for backward compatibility)
    required_treatments = @release_note.get_required_treatments
    Rails.logger.info "Required treatments for thickness: #{required_treatments.length}"

    # Initialize the measurements structure
    @release_note.measured_thicknesses = { 'measurements' => [] }

    # Process each thickness measurement field
    params.each do |param_name, param_value|
      next unless param_name.to_s.start_with?('thickness_measurement_')

      # Extract treatment_id from field name (thickness_measurement_abc123def456)
      treatment_id = param_name.to_s.sub('thickness_measurement_', '')

      # Find the corresponding treatment info
      treatment_info = required_treatments.find { |t| t[:treatment_id] == treatment_id }
      next unless treatment_info

      Rails.logger.info "Processing thickness measurement: #{treatment_id} = #{param_value}"

      if param_value.present?
        success = @release_note.set_thickness_measurement(treatment_id, param_value, treatment_info)
        Rails.logger.info "Set thickness measurement for #{treatment_id}: #{success}"

        unless success
          @release_note.errors.add(:measured_thicknesses,
            "Invalid thickness value for #{treatment_info[:display_name]}")
        end
      elsif @release_note.requires_thickness_measurements?
        # If thickness is required but not provided, the model validation will catch this
        Rails.logger.warn "Missing required thickness for treatment: #{treatment_id}"
      end
    end

    Rails.logger.info "Final measured_thicknesses: #{@release_note.measured_thicknesses}"
  end
end
