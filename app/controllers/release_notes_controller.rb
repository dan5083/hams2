# app/controllers/release_notes_controller.rb - Updated to handle Elcometer readings arrays
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

    # Add pagination - 20 items per page to match customer orders
    @release_notes = @release_notes.page(params[:page]).per(20)
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
    unless @release_note.can_be_edited?
      redirect_to @release_note, alert: 'Cannot edit voided release notes.'
      return
    end

    # Store original quantities for comparison (used in form warnings)
    @original_quantity_accepted = @release_note.quantity_accepted
    @original_quantity_rejected = @release_note.quantity_rejected
  end

  def update
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
    # Check if measurements were provided via JSON (from Elcometer or form submission)
    params[:release_note][:measured_thicknesses].present? ||
    # Check if individual thickness readings fields were provided (anodic)
    params.keys.any? { |key| key.to_s.start_with?('thickness_readings_') } ||
    # Check if ENP measurement fields were provided
    params.keys.any? { |key| key.to_s.start_with?('enp_measurements_') } ||
    # Check if legacy individual thickness fields were provided (backward compatibility)
    params.keys.any? { |key| key.to_s.start_with?('thickness_measurement_') }
  end

def process_thickness_measurements
  Rails.logger.info "Processing thickness measurements for release note"

  # Try to process JSON data from form submission first
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
    end
  end

  # Process individual measurement fields
  required_treatments = @release_note.get_required_treatments
  @release_note.measured_thicknesses = { 'measurements' => [] }

  # Process anodic thickness readings fields (Elcometer and manual entry)
  readings_fields = params.select { |key, _|
    key.to_s.start_with?('thickness_readings_') || key.to_s.start_with?('thickness_measurement_')
  }

  readings_fields.each do |field_name, field_value|
    # Extract treatment_id (works for both field name formats)
    treatment_id = field_name.to_s.sub(/^thickness_(readings|measurement)_/, '')

    treatment_info = required_treatments.find { |t| t[:treatment_id] == treatment_id }
    next unless treatment_info

    begin
      # Parse readings - handle both JSON arrays and single values
      readings = if field_value.is_a?(String) && field_value.strip.start_with?('[')
        JSON.parse(field_value) # Elcometer: "[70.5, 70.7, 69.9]"
      elsif field_value.present?
        [field_value] # Manual entry: "25.4" -> [25.4]
      else
        []
      end

      if readings.any?
        Rails.logger.info "Processing #{readings.count} anodic reading(s) for treatment #{treatment_id}"
        success = @release_note.set_thickness_measurement(treatment_id, readings, treatment_info)

        unless success
          @release_note.errors.add(:measured_thicknesses,
            "Invalid readings for #{treatment_info[:display_name]}")
        end
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse readings for #{treatment_id}: #{e.message}"
      @release_note.errors.add(:measured_thicknesses,
        "Invalid data format for #{treatment_info[:display_name]}")
    end
  end

  # Process ENP measurement fields
  enp_fields = params.select { |key, _| key.to_s.start_with?('enp_measurements_') }

  enp_fields.each do |field_name, field_value|
    # Extract treatment_id: enp_measurements_abc123
    treatment_id = field_name.to_s.sub(/^enp_measurements_/, '')

    treatment_info = required_treatments.find { |t| t[:treatment_id] == treatment_id }
    next unless treatment_info

    begin
      # Parse ENP measurements JSON
      enp_data = if field_value.is_a?(String) && field_value.strip.present?
        JSON.parse(field_value)
      else
        []
      end

      if enp_data.any?
        Rails.logger.info "Processing #{enp_data.count} ENP measurement(s) for treatment #{treatment_id}"

        # Add enp_type to treatment_info if available
        treatment_info[:enp_type] = treatment_info[:process_type]

        success = @release_note.set_enp_measurements(treatment_id, enp_data, treatment_info)

        unless success
          @release_note.errors.add(:measured_thicknesses,
            "Invalid ENP measurements for #{treatment_info[:display_name]}")
        end
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse ENP measurements for #{treatment_id}: #{e.message}"
      @release_note.errors.add(:measured_thicknesses,
        "Invalid ENP data format for #{treatment_info[:display_name]}")
    end
  end
end
end

# =============================================================================
# CHEAT SHEET: Adding Thickness Measurement Requirements to Parts
# =============================================================================
#
# PROBLEM: When copying parts, locked_operations contain anodising processes
# but customisation_data["operation_selection"]["treatments"] is empty.
# This causes release notes to NOT require thickness measurements even though
# the part is aerospace/defense and has anodising.
#
# SOLUTION: Manually add the treatment to the treatments field using Heroku console.
#
# -----------------------------------------------------------------------------
# 1. FIND PROBLEMATIC PARTS FOR A CUSTOMER
# -----------------------------------------------------------------------------
#
# customer = Organization.find_by("name ILIKE ?", "%CUSTOMER_NAME%")
# parts = Part.where(customer: customer, enabled: true)
#
# parts.each do |part|
#   treatments = part.get_treatments
#   if part.aerospace_defense? && treatments.empty? && part.locked_for_editing?
#     # Check if they have anodising in locked operations
#     has_anodising = part.locked_operations.any? do |op|
#       op_text = op["operation_text"]&.downcase || ""
#       op_name = op["display_name"]&.downcase || ""
#       op_text.include?("anodis") || op_name.include?("anodis")
#     end
#     puts "❌ #{part.display_name} - needs fixing" if has_anodising
#   end
# end
#
# -----------------------------------------------------------------------------
# 2. FIX A PART - Add Thickness Measurement Requirement
# -----------------------------------------------------------------------------
#
# CHROMIC ANODISING:
# ------------------
# part = Part.find_by(part_number: 'PART-NUMBER-HERE')
# part.customisation_data["operation_selection"]["treatments"] = [
#   {
#     "type" => "chromic_anodising",
#     "operation_id" => "CHROMIC_22V",
#     "selected_jig_type" => "titanium_wire",
#     "target_thickness" => 5
#   }
# ].to_json
# part.save!
#
# HARD ANODISING:
# ---------------
# part = Part.find_by(part_number: 'PART-NUMBER-HERE')
# part.customisation_data["operation_selection"]["treatments"] = [
#   {
#     "type" => "hard_anodising",
#     "operation_id" => "HARD_ANODISING",
#     "selected_jig_type" => "titanium_wire",
#     "target_thickness" => 25
#   }
# ].to_json
# part.save!
#
# STANDARD ANODISING:
# -------------------
# part = Part.find_by(part_number: 'PART-NUMBER-HERE')
# part.customisation_data["operation_selection"]["treatments"] = [
#   {
#     "type" => "standard_anodising",
#     "operation_id" => "STANDARD_ANODISING",
#     "selected_jig_type" => "titanium_wire",
#     "target_thickness" => 15
#   }
# ].to_json
# part.save!
#
# MULTIPLE TREATMENTS (e.g., Chromic + Hard):
# --------------------------------------------
# part = Part.find_by(part_number: 'PART-NUMBER-HERE')
# part.customisation_data["operation_selection"]["treatments"] = [
#   {
#     "type" => "chromic_anodising",
#     "operation_id" => "CHROMIC_22V",
#     "selected_jig_type" => "titanium_wire",
#     "target_thickness" => 5
#   },
#   {
#     "type" => "hard_anodising",
#     "operation_id" => "HARD_ANODISING",
#     "selected_jig_type" => "titanium_wire",
#     "target_thickness" => 25
#   }
# ].to_json
# part.save!
#
# -----------------------------------------------------------------------------
# 3. VERIFY THE FIX
# -----------------------------------------------------------------------------
#
# wo = part.works_orders.last
# if wo
#   rn = wo.release_notes.build
#   puts "✅ Requires thickness: #{rn.requires_thickness_measurements?}"
#   puts "Required treatments: #{rn.get_required_treatments.inspect}"
# end
#
# -----------------------------------------------------------------------------
# NOTES:
# - Adjust target_thickness to match your specification
# - Common jig types: "titanium_wire", "titanium_bar", "aluminium_bar"
# - Valid types: "chromic_anodising", "hard_anodising", "standard_anodising"
# - For multiple treatments, just add more hashes to the array
# =============================================================================
