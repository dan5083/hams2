# app/models/part_processing_instruction.rb
class PartProcessingInstruction < ApplicationRecord
  belongs_to :part
  belongs_to :customer, class_name: 'Organization'
  belongs_to :replaces, class_name: 'PartProcessingInstruction', optional: true

  has_many :works_orders, foreign_key: :ppi_id, dependent: :restrict_with_error
  has_many :replaced_by, class_name: 'PartProcessingInstruction',
           foreign_key: :replaces_id, dependent: :nullify

  validates :part_number, presence: true
  validates :part_issue, presence: true
  validates :part_description, presence: true
  validates :specification, presence: true
  validates :process_type, inclusion: { in: ProcessBuilder.available_types }
  validate :validate_treatments

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :for_part_number, ->(part_number) { where("part_number ILIKE ?", "%#{part_number}%") }
  scope :for_part_issue, ->(part_issue) { where("part_issue ILIKE ?", "%#{part_issue}%") }

  before_validation :set_part_from_details, if: :part_details_changed?
  before_validation :build_specification_from_operations, if: :treatments_changed?
  after_initialize :set_defaults, if: :new_record?
  after_create :disable_replaced_ppi

  def display_name
    "#{part_number}-#{part_issue}"
  end

  def enable!
    update!(enabled: true)
  end

  def disable!
    update!(enabled: false)
  end

  def can_be_deleted?
    works_orders.empty? && replaced_by.empty?
  end

  def active?
    enabled && part&.enabled && customer&.active?
  end

  # Get aerospace/defense flag from customisation data
  def aerospace_defense?
    operation_selection["aerospace_defense"] == true || operation_selection["aerospace_defense"] == "true"
  end

  # Get selected ENP post-heat treatment
  def selected_enp_heat_treatment
    operation_selection["selected_enp_heat_treatment"]
  end

  # Get selected ENP pre-heat treatment
  def selected_enp_pre_heat_treatment
    operation_selection["selected_enp_pre_heat_treatment"]
  end

  # Check if ENP post-heat treatment is selected
  def enp_heat_treatment_selected?
    selected_enp_heat_treatment.present? && selected_enp_heat_treatment != 'none'
  end

  # Check if ENP pre-heat treatment is selected
  def enp_pre_heat_treatment_selected?
    selected_enp_pre_heat_treatment.present? && selected_enp_pre_heat_treatment != 'none'
  end

  # UPDATED: Main method - get operations with correct ordering including water break test and ENP heat treatments
  def get_operations_with_auto_ops
    treatments = get_treatments
    return [] if treatments.empty?

    sequence = []
    has_enp = treatments.any? { |t| t[:operation].process_type == 'electroless_nickel_plating' }

    # Beginning ops (always first)
    safe_add_to_sequence(sequence, OperationLibrary::ContractReviewOperations.get_contract_review_operation, "Contract Review")
    safe_add_to_sequence(sequence, OperationLibrary::InspectFinalInspectVatInspect.get_incoming_inspection_operation, "Incoming Inspection")
    safe_add_to_sequence(sequence, OperationLibrary::InspectFinalInspectVatInspect.get_vat_inspection_operation, "VAT Inspection")

    # ENP Pre-Heat Treatment (before any treatment cycles)
    add_enp_pre_heat_treatment_if_selected(sequence) if has_enp

    # Treatment cycles (main processing) - each with their own jig
    treatments.each { |treatment| add_treatment_cycle(sequence, treatment, has_enp) }

    # Post-treatment operations in correct order

    # 1. ENP Post-Heat Treatment (after all treatment cycles but before ENP Strip/Mask)
    add_enp_heat_treatment_if_selected(sequence) if has_enp

    # 2. ENP Strip/Mask operations (before final inspection!)
    add_enp_strip_mask_ops(sequence) if has_enp_strip_mask_operations?

    # 3. Final inspection (after all processing including masking removal and heat treatment)
    safe_add_to_sequence(sequence, OperationLibrary::InspectFinalInspectVatInspect.get_final_inspection_operation, "Final Inspection")

    # 4. Pack (always last)
    safe_add_to_sequence(sequence, OperationLibrary::PackOperations.get_pack_operation, "Pack")

    # 5. Insert water break test if required (after degrease operations)
    if defined?(OperationLibrary::WaterBreakOperations)
      sequence = OperationLibrary::WaterBreakOperations.insert_water_break_test_if_required(
        sequence,
        aerospace_defense: aerospace_defense?
      )
    end

    # Remove any nil entries that might have been added
    sequence.compact
  end

  # Get treatments from nested structure
  def get_treatments
    treatments_data = operation_selection["treatments"] || []

    # Get operations with target thickness for ENP time interpolation
    target_thickness = get_enp_target_thickness_from_treatments(treatments_data)
    all_operations = Operation.all_operations(target_thickness)

    treatments_data.map do |data|
      operation = all_operations.find { |op| op.id == data["operation_id"] }
      next unless operation

      {
        operation: operation,
        treatment_data: data,
        masking: data["masking"] || {},
        stripping: data["stripping"] || {},
        sealing: data["sealing"] || {},
        dye: data["dye"] || {},
        ptfe: data["ptfe"] || {}
      }
    end.compact
  end

  def operation_selection
    customisation_data["operation_selection"] || {}
  end

  # REMOVED: selected_jig_type method - no longer used as jigs are per-treatment
  # def selected_jig_type
  #   operation_selection["selected_jig_type"]
  # end

  def operations_text
    get_operations_with_auto_ops.map.with_index(1) do |operation, index|
      "Operation #{index}: #{operation.operation_text}"
    end.join("\n\n")
  end

  def operations_summary
    ops = get_operations_with_auto_ops
    return "No operations selected" if ops.empty?
    ops.map(&:display_name).join(" → ")
  end

  # UPDATED: Class method for frontend preview with per-treatment jig support
  def self.simulate_operations_with_auto_ops(treatments_data, selected_jig_type = nil, selected_alloy = nil, selected_operations = nil, enp_strip_type = 'nitric', aerospace_defense = false, selected_enp_heat_treatment = nil, selected_enp_pre_heat_treatment = nil)
    return [] if treatments_data.blank?

    mock_ppi = new
    mock_ppi.customisation_data = {
      "operation_selection" => {
        "treatments" => treatments_data,
        "selected_operations" => selected_operations || [],
        "enp_strip_type" => enp_strip_type,
        "aerospace_defense" => aerospace_defense,
        "selected_enp_heat_treatment" => selected_enp_heat_treatment,
        "selected_enp_pre_heat_treatment" => selected_enp_pre_heat_treatment
      }
    }

    # Use the ordering from the instance method
    mock_ppi.get_operations_with_auto_ops.map do |operation|
      {
        id: operation.id,
        display_name: operation.display_name,
        operation_text: operation.operation_text,
        auto_inserted: operation.auto_inserted?
      }
    end
  end

  # ENP Strip Mask - check if selected operations include ENP strip/mask ops
  def has_enp_strip_mask_operations?
    enp_ids = ['ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC', 'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL']
    (operation_selection["selected_operations"] || []).any? { |id| enp_ids.include?(id) }
  end

  private

  # Helper method to safely add operations to sequence with nil checking
  def safe_add_to_sequence(sequence, operation, description)
    if operation.nil?
      Rails.logger.error "NIL OPERATION: #{description}"
    else
      sequence << operation
    end
  end

  # Add ENP pre-heat treatment if selected (before jigging)
  def add_enp_pre_heat_treatment_if_selected(sequence)
    return unless enp_pre_heat_treatment_selected?
    return unless defined?(OperationLibrary::EnpHeatTreatments)

    pre_heat_treatment = OperationLibrary::EnpHeatTreatments.get_heat_treatment_operation(selected_enp_pre_heat_treatment)
    if pre_heat_treatment
      # Create a duplicate with modified text to indicate it's pre-heat
      pre_heat_op = Operation.new(
        id: "PRE_#{pre_heat_treatment.id}",
        process_type: 'enp_pre_heat_treatment',
        operation_text: "**Pre-Heat:** #{pre_heat_treatment.operation_text}",
        specifications: pre_heat_treatment.specifications
      )
      safe_add_to_sequence(sequence, pre_heat_op, "ENP Pre-Heat Treatment")
    else
      Rails.logger.warn "ENP Pre-Heat Treatment not found: #{selected_enp_pre_heat_treatment}"
    end
  end

  # Add ENP post-heat treatment if selected (after unjig)
  def add_enp_heat_treatment_if_selected(sequence)
    return unless enp_heat_treatment_selected?
    return unless defined?(OperationLibrary::EnpHeatTreatments)

    heat_treatment = OperationLibrary::EnpHeatTreatments.get_heat_treatment_operation(selected_enp_heat_treatment)
    if heat_treatment
      # Create a duplicate with modified text to indicate it's post-heat
      post_heat_op = Operation.new(
        id: "POST_#{heat_treatment.id}",
        process_type: 'enp_post_heat_treatment',
        operation_text: "**Post-Heat:** #{heat_treatment.operation_text}",
        specifications: heat_treatment.specifications
      )
      safe_add_to_sequence(sequence, post_heat_op, "ENP Post-Heat Treatment")
    else
      Rails.logger.warn "ENP Post-Heat Treatment not found: #{selected_enp_heat_treatment}"
    end
  end

  # UPDATED: Standard treatment cycle with per-treatment jig support
  def add_treatment_cycle(sequence, treatment, has_enp)
    op = treatment[:operation]
    treatment_data = treatment[:treatment_data]
    masking = treatment[:masking]
    stripping = treatment[:stripping]
    sealing = treatment[:sealing]
    dye = treatment[:dye]
    ptfe = treatment[:ptfe]

    # Get jig type for this specific treatment
    treatment_jig_type = treatment_data["selected_jig_type"]

    # ENP has special workflow - no masking/stripping/dye/PTFE modifiers
    if op.process_type == 'electroless_nickel_plating'
      add_enp_cycle(sequence, op, treatment_data, treatment_jig_type)
      return
    end

    # Standard anodising/chemical conversion cycle
    # 1. Masking
    if masking["enabled"] && masking["methods"].present?
      safe_add_to_sequence(sequence, OperationLibrary::Masking.get_masking_operation(masking["methods"]), "Masking")
      safe_add_to_sequence(sequence, OperationLibrary::Masking.get_masking_inspection_operation, "Masking Inspection")
    end

    # 2. Jig - USE TREATMENT-SPECIFIC JIG TYPE
    safe_add_to_sequence(sequence, OperationLibrary::JigUnjig.get_jig_operation(treatment_jig_type), "Jig")

    # 3. Degrease + rinse
    if needs_degrease?(op)
      degrease = OperationLibrary::DegreaseOperations.get_degrease_operation
      safe_add_to_sequence(sequence, degrease, "Degrease")
      safe_add_to_sequence(sequence, get_rinse(degrease, has_enp, masking), "Rinse after Degrease")
    end

    # 4. Pretreatments + rinses
    if needs_pretreatment?(op)
      pretreatments = OperationLibrary::Pretreatments.get_pretreatment_sequence([op], nil)
      pretreatments.each do |pretreat|
        safe_add_to_sequence(sequence, pretreat, "Pretreatment")
        safe_add_to_sequence(sequence, get_rinse(pretreat, has_enp, masking), "Rinse after Pretreatment") unless pretreat.process_type == 'rinse'
      end
    end

    # 5. Stripping + rinse
    if stripping["enabled"] && stripping["type"].present? && stripping["method"].present?
      strip_op = OperationLibrary::Stripping.get_stripping_operation(stripping["type"], stripping["method"])
      safe_add_to_sequence(sequence, strip_op, "Stripping")
      safe_add_to_sequence(sequence, get_rinse(strip_op, has_enp, masking), "Rinse after Stripping")
    end

    # 6. Main operation + rinse
    safe_add_to_sequence(sequence, op, "Main Operation")
    safe_add_to_sequence(sequence, get_rinse(op, has_enp, masking), "Rinse after Main Operation")

    # 7. Dye + rinse (for anodising operations only)
    if dye["enabled"] && dye["color"].present? && is_anodising?(op)
      dye_op = OperationLibrary::Dye.get_dye_operation(dye["color"])
      if dye_op
        safe_add_to_sequence(sequence, dye_op, "Dye")
        safe_add_to_sequence(sequence, get_rinse(dye_op, has_enp, masking), "Rinse after Dye")
      end
    end

    # 8. Sealing + rinse
    if sealing["enabled"] && sealing["type"].present? && is_anodising?(op)
      seal_op = OperationLibrary::Sealing.get_sealing_operation(sealing["type"])
      if seal_op
        safe_add_to_sequence(sequence, seal_op, "Sealing")
        safe_add_to_sequence(sequence, get_rinse(seal_op, has_enp, masking), "Rinse after Sealing")
      end
    end

    # 9. PTFE + rinse (for anodising operations only, after sealing)
    if ptfe["enabled"] && is_anodising?(op)
      ptfe_op = OperationLibrary::Ptfe.get_ptfe_operation
      if ptfe_op
        safe_add_to_sequence(sequence, ptfe_op, "PTFE")
        safe_add_to_sequence(sequence, get_rinse(ptfe_op, has_enp, masking), "Rinse after PTFE")
      end
    end

    # 10. Unjig
    safe_add_to_sequence(sequence, OperationLibrary::JigUnjig.get_unjig_operation, "Unjig")

    # 11. Masking removal - simplified logic
    if masking["enabled"] && masking["methods"].present?
      if OperationLibrary::Masking.masking_removal_required?(masking["methods"])
        OperationLibrary::Masking.get_masking_removal_operations.each do |removal_op|
          safe_add_to_sequence(sequence, removal_op, "Masking Removal")
        end
      end
    end
  end

  # UPDATED: ENP cycle - USE TREATMENT-SPECIFIC JIG TYPE
  def add_enp_cycle(sequence, enp_op, treatment_data, treatment_jig_type)
    # 1. Jig - USE TREATMENT-SPECIFIC JIG TYPE
    safe_add_to_sequence(sequence, OperationLibrary::JigUnjig.get_jig_operation(treatment_jig_type), "ENP Jig")

    # 2. Degrease + rinse
    degrease = OperationLibrary::DegreaseOperations.get_degrease_operation
    safe_add_to_sequence(sequence, degrease, "ENP Degrease")
    safe_add_to_sequence(sequence, get_rinse(degrease, true, {}), "ENP Rinse after Degrease")

    # 3. ENP pretreatments + rinses
    if defined?(OperationLibrary::Pretreatments)
      # Get the selected alloy for the ENP treatment from the treatment data
      selected_alloy = get_selected_enp_alloy_for_treatment_data(treatment_data)
      if selected_alloy
        pretreatments = OperationLibrary::Pretreatments.get_pretreatment_sequence([enp_op], selected_alloy)
        pretreatments.each do |pretreat|
          safe_add_to_sequence(sequence, pretreat, "ENP Pretreatment")
          safe_add_to_sequence(sequence, get_rinse(pretreat, true, {}), "ENP Rinse after Pretreatment") unless pretreat.process_type == 'rinse'
        end
      end
    end

    # 4. ENP operation + rinse
    safe_add_to_sequence(sequence, enp_op, "ENP Operation")
    safe_add_to_sequence(sequence, get_rinse(enp_op, true, {}), "ENP Rinse after Operation")

    # 5. Unjig
    safe_add_to_sequence(sequence, OperationLibrary::JigUnjig.get_unjig_operation, "ENP Unjig")
  end

  def needs_degrease?(op)
    ['standard_anodising', 'hard_anodising', 'chromic_anodising', 'chemical_conversion', 'electroless_nickel_plating'].include?(op.process_type)
  end

  def needs_pretreatment?(op)
    defined?(OperationLibrary::Pretreatments) && needs_degrease?(op)
  end

  def is_anodising?(op)
    ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(op.process_type)
  end

  def get_rinse(op, has_enp, masking = {})
    OperationLibrary::RinseOperations.get_rinse_operation(op, ppi_contains_electroless_nickel: has_enp, masking: masking)
  end

  def get_selected_alloy(op)
    op.process_type == 'electroless_nickel_plating' ? operation_selection["selected_enp_alloy"] : nil
  end

  def add_enp_strip_mask_ops(sequence)
    return unless defined?(OperationLibrary::EnpStripMask)
    strip_type = operation_selection["enp_strip_type"] || 'nitric'
    sequence.concat(OperationLibrary::EnpStripMask.operations(strip_type))
  end

  # Helper method to get ENP alloy from treatment data
  def get_selected_enp_alloy_for_treatment_data(treatment_data)
    return nil unless treatment_data && treatment_data["selected_alloy"]

    # Convert from form format to pretreatment format
    convert_alloy_to_pretreatment_format(treatment_data["selected_alloy"])
  end

  # Convert form alloy values to pretreatment sequence keys
  def convert_alloy_to_pretreatment_format(form_alloy)
    mapping = {
      'steel' => 'STEEL',
      'stainless_steel' => 'STAINLESS_STEEL',
      '316_stainless_steel' => 'THREE_ONE_SIX_STAINLESS_STEEL',
      'aluminium' => 'ALUMINIUM',
      'copper' => 'COPPER',
      'brass' => 'BRASS',
      '2000_series_alloys' => 'TWO_THOUSAND_SERIES_ALLOYS',
      'stainless_steel_with_oxides' => 'STAINLESS_STEEL_WITH_OXIDES',
      'copper_sans_electrical_contact' => 'COPPER_SANS_ELECTRICAL_CONTACT',
      'cast_aluminium_william_cope' => 'CAST_ALUMINIUM_WILLIAM_COPE',
      'mclaren_sta142_procedure_d' => 'MCLAREN_STA142_PROCEDURE_D'
    }

    mapping[form_alloy]
  end

  # Validation and setup
  def validate_treatments
    treatments_data = operation_selection["treatments"] || []
    errors.add(:base, "cannot select more than 5 treatments") if treatments_data.length > 5

    # NEW: Validate that each treatment has a jig type selected
    treatments_data.each_with_index do |treatment, index|
      if treatment["selected_jig_type"].blank?
        errors.add(:base, "treatment #{index + 1} must have a jig type selected")
      end
    end
  end

  def treatments_changed?
    customisation_data_changed? && customisation_data_change&.any? { |before, after|
      (before&.dig("operation_selection", "treatments") || []) != (after&.dig("operation_selection", "treatments") || [])
    }
  end

  def build_specification_from_operations
    self.specification = operations_text if get_treatments.any?
  end

  def set_defaults
    self.enabled = true if enabled.nil?
    self.customisation_data = {} if customisation_data.blank?
  end

  def part_details_changed?
    part_number_changed? || part_issue_changed? || customer_id_changed?
  end

  def set_part_from_details
    return unless part_number.present? && part_issue.present? && customer_id.present?
    self.part = Part.ensure(customer_id: customer_id, part_number: part_number, part_issue: part_issue)
  end

  def disable_replaced_ppi
    replaces&.disable! if replaces_id.present?
  end

  # Helper method to extract ENP target thickness from treatments data for operation interpolation
  def get_enp_target_thickness_from_treatments(treatments_data)
    enp_treatment = treatments_data.find { |t| t["type"] == "electroless_nickel_plating" && t["target_thickness"] }
    enp_treatment&.dig("target_thickness")&.to_f
  end
end
