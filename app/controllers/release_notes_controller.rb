# app/controllers/release_notes_controller.rb - Updated to handle multi-batch measurements
class ReleaseNotesController < ApplicationController
  before_action :set_release_note, only: [:show, :edit, :update, :destroy, :void, :pdf]
  before_action :set_works_order, only: [:new, :create]

  def index
    @release_notes = ReleaseNote.includes(:works_order, :issued_by, :invoice_item)
                                .order(number: :desc)

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

    if params[:customer_id].present?
      @release_notes = @release_notes.joins(works_order: { customer_order: :customer })
                                     .where(customer_orders: { customer_id: params[:customer_id] })
    end

    if params[:search].present?
      @release_notes = @release_notes.where("number::text ILIKE ?", "%#{params[:search]}%")
    end

    @customers = Organization.customers.enabled.order(:name)
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

    @original_quantity_accepted = @release_note.quantity_accepted
    @original_quantity_rejected = @release_note.quantity_rejected
  end

  def update
    unless @release_note.can_be_edited?
      redirect_to @release_note, alert: 'Cannot edit voided release notes.'
      return
    end

    if thickness_measurements_provided?
      process_thickness_measurements
    end

    was_invoiced = @release_note.invoiced?

    if @release_note.update(release_note_params)
      success_message = 'Release note was successfully updated.'

      if was_invoiced && (@release_note.quantity_accepted_previously_changed? || @release_note.quantity_rejected_previously_changed?)
        success_message += ' Note: This release note has already been invoiced - the invoice amounts will not be affected by quantity changes.'
      end

      redirect_to @release_note, notice: success_message
    else
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
    @company_name    = "Hard Anodising Surface Treatments Ltd"
    @trading_address = "Firs Industrial Estate, Rickets Close\nKidderminster, DY11 7QN"

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        pdf = Grover.new(
          render_to_string(
            template: 'release_notes/pdf',
            layout: false,
            locals: {
              release_note: @release_note,
              company_name: @company_name,
              trading_address: @trading_address
            }
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
    # Primary JSON payload (from submit handler)
    return true if params[:release_note][:measured_thicknesses].present?

    # Per-batch anodic fields: thickness_readings_<id>_b<n>  OR legacy thickness_readings_<id>
    return true if params.keys.any? { |k|
      k.to_s.start_with?('thickness_readings_') || k.to_s.start_with?('thickness_measurement_')
    }

    # Per-batch ENP fields: enp_measurements_<id>_b<n>  OR legacy enp_measurements_<id>
    return true if params.keys.any? { |k| k.to_s.start_with?('enp_measurements_') }

    false
  end

  # ---------------------------------------------------------------------------
  # Primary path: the form's submit handler packs everything into a single JSON
  # blob at release_note[measured_thicknesses].  The blob now uses the batches
  # structure:
  #
  #   { "measurements": [
  #       { "treatment_id": "abc123",
  #         "process_type": "hard_anodising",
  #         "display_name": "Hard Anodising",
  #         "target_thickness": 25,
  #         "batches": [
  #           { "batch_number": 1, "readings": [70.5, 70.7, ...] },
  #           { "batch_number": 2, "readings": [71.0, 70.8, ...] }
  #         ]
  #       },
  #       { "treatment_id": "def456",
  #         "process_type": "electroless_nickel_plating",
  #         "batches": [
  #           { "batch_number": 1, "enp_measurements": [{...}, ...] },
  #           { "batch_number": 2, "enp_measurements": [{...}, ...] }
  #         ]
  #       }
  #     ]
  #   }
  #
  # Fallback path: individual per-batch fields (legacy or if JS failed).
  #   Anodic field names: thickness_readings_<treatment_id>_b<n>
  #   ENP field names:    enp_measurements_<treatment_id>_b<n>
  # ---------------------------------------------------------------------------
  def process_thickness_measurements
    Rails.logger.info "Processing thickness measurements (batch-aware)"

    # --- Primary path: JSON blob ---
    if release_note_params[:measured_thicknesses].present?
      begin
        json_data = JSON.parse(release_note_params[:measured_thicknesses])
        if json_data.is_a?(Hash) && json_data['measurements'].is_a?(Array)
          Rails.logger.info "Processing JSON payload with #{json_data['measurements'].length} measurements"
          @release_note.measured_thicknesses = json_data
          return
        end
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse JSON thickness data: #{e.message}"
      end
    end

    # --- Fallback path: individual fields ---
    required_treatments = @release_note.get_required_treatments
    @release_note.measured_thicknesses = { 'measurements' => [] }

    # Collect anodic per-batch fields
    # Field name patterns:
    #   thickness_readings_<treatment_id>_b<n>    (new batch format)
    #   thickness_readings_<treatment_id>          (legacy single batch)
    #   thickness_measurement_<treatment_id>       (older legacy)
    anodic_fields = params.select { |k, _|
      k.to_s.start_with?('thickness_readings_') || k.to_s.start_with?('thickness_measurement_')
    }

    # Group by treatment_id → { treatment_id => { batch_number => field_value } }
    anodic_by_treatment = {}
    anodic_fields.each do |field_name, field_value|
      base = field_name.to_s.sub(/^thickness_(readings|measurement)_/, '')

      treatment_id, batch_number = if base =~ /^(.+)_b(\d+)$/
        [$1, $2.to_i]
      else
        [base, 1]
      end

      anodic_by_treatment[treatment_id] ||= {}
      anodic_by_treatment[treatment_id][batch_number] = field_value
    end

    anodic_by_treatment.each do |treatment_id, batches_hash|
      treatment_info = required_treatments.find { |t| t[:treatment_id] == treatment_id }
      next unless treatment_info

      batches = batches_hash
        .map { |batch_number, field_value| { 'batch_number' => batch_number, 'readings' => parse_readings_field(field_value) } }
        .sort_by { |b| b['batch_number'] }

      if batches.any? { |b| b['readings'].any? }
        Rails.logger.info "Processing #{batches.count} anodic batch(es) for treatment #{treatment_id}"
        success = @release_note.set_thickness_measurement(treatment_id, batches, treatment_info)
        unless success
          @release_note.errors.add(:measured_thicknesses, "Invalid readings for #{treatment_info[:display_name]}")
        end
      end
    end

    # Collect ENP per-batch fields
    # Field name patterns:
    #   enp_measurements_<treatment_id>_b<n>    (new batch format)
    #   enp_measurements_<treatment_id>          (legacy single batch)
    enp_fields = params.select { |k, _| k.to_s.start_with?('enp_measurements_') }

    enp_by_treatment = {}
    enp_fields.each do |field_name, field_value|
      base = field_name.to_s.sub(/^enp_measurements_/, '')

      treatment_id, batch_number = if base =~ /^(.+)_b(\d+)$/
        [$1, $2.to_i]
      else
        [base, 1]
      end

      enp_by_treatment[treatment_id] ||= {}
      enp_by_treatment[treatment_id][batch_number] = field_value
    end

    enp_by_treatment.each do |treatment_id, batches_hash|
      treatment_info = required_treatments.find { |t| t[:treatment_id] == treatment_id }
      next unless treatment_info

      batches = batches_hash.map do |batch_number, field_value|
        enp_data = begin
          field_value.present? ? JSON.parse(field_value) : []
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse ENP batch #{batch_number} for #{treatment_id}: #{e.message}"
          @release_note.errors.add(:measured_thicknesses, "Invalid ENP data format for #{treatment_info[:display_name]} batch #{batch_number}")
          []
        end
        { 'batch_number' => batch_number, 'enp_measurements' => enp_data }
      end.sort_by { |b| b['batch_number'] }

      if batches.any? { |b| b['enp_measurements'].any? }
        Rails.logger.info "Processing #{batches.count} ENP batch(es) for treatment #{treatment_id}"
        treatment_info[:enp_type] = treatment_info[:process_type]
        success = @release_note.set_enp_measurements(treatment_id, batches, treatment_info)
        unless success
          @release_note.errors.add(:measured_thicknesses, "Invalid ENP measurements for #{treatment_info[:display_name]}")
        end
      end
    end
  end

  # Parses a readings field value which may be a JSON array ("[]") or a single value.
  def parse_readings_field(field_value)
    return [] if field_value.blank?

    if field_value.is_a?(String) && field_value.strip.start_with?('[')
      begin
        JSON.parse(field_value)
      rescue JSON::ParserError
        []
      end
    else
      [field_value]
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
# HARD ANODISING:
# part = Part.find_by(part_number: 'PART-NUMBER-HERE')
# part.customisation_data["operation_selection"]["treatments"] = [
#   { "type" => "hard_anodising", "operation_id" => "HARD_ANODISING",
#     "selected_jig_type" => "titanium_wire", "target_thickness" => 25 }
# ].to_json
# part.save!
#
# CHROMIC ANODISING:
# part.customisation_data["operation_selection"]["treatments"] = [
#   { "type" => "chromic_anodising", "operation_id" => "CHROMIC_22V",
#     "selected_jig_type" => "titanium_wire", "target_thickness" => 5 }
# ].to_json
# part.save!
#
# MULTIPLE TREATMENTS:
# part.customisation_data["operation_selection"]["treatments"] = [
#   { "type" => "chromic_anodising", ... },
#   { "type" => "hard_anodising", ... }
# ].to_json
# part.save!
#
# Valid types: "chromic_anodising", "hard_anodising", "standard_anodising"
# Common jig types: "titanium_wire", "titanium_bar", "aluminium_bar"
# =============================================================================
