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

  # Main method - get operations with treatment cycles
  def get_operations_with_auto_ops
    treatments = get_treatments
    return [] if treatments.empty?

    sequence = []
    has_enp = treatments.any? { |t| t[:operation].process_type == 'electroless_nickel_plating' }

    # Beginning ops
    sequence << OperationLibrary::ContractReviewOperations.get_contract_review_operation
    sequence << OperationLibrary::InspectFinalInspectVatInspect.get_incoming_inspection_operation
    sequence << OperationLibrary::InspectFinalInspectVatInspect.get_vat_inspection_operation

    # Treatment cycles
    treatments.each { |treatment| add_treatment_cycle(sequence, treatment, has_enp) }

    # Ending ops
    add_enp_strip_mask_ops(sequence) if has_enp_strip_mask_operations?
    sequence << OperationLibrary::InspectFinalInspectVatInspect.get_final_inspection_operation
    sequence << OperationLibrary::PackOperations.get_pack_operation

    sequence
  end

  # Get treatments from nested structure
  def get_treatments
    treatments_data = operation_selection["treatments"] || []
    all_operations = Operation.all_operations

    treatments_data.map do |data|
      operation = all_operations.find { |op| op.id == data["operation_id"] }
      next unless operation

      {
        operation: operation,
        treatment_data: data,
        masking: data["masking"] || {},
        stripping: data["stripping"] || {},
        sealing: data["sealing"] || {}
      }
    end.compact
  end

  def operation_selection
    customisation_data["operation_selection"] || {}
  end

  def selected_jig_type
    operation_selection["selected_jig_type"]
  end

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

  # Class method for frontend preview
  def self.simulate_operations_with_auto_ops(treatments_data, selected_jig_type = nil, selected_alloy = nil)
    return [] if treatments_data.blank?

    mock_ppi = new
    mock_ppi.customisation_data = {
      "operation_selection" => {
        "treatments" => treatments_data,
        "selected_jig_type" => selected_jig_type
      }
    }

    mock_ppi.get_operations_with_auto_ops.map do |operation|
      {
        id: operation.id,
        display_name: operation.display_name,
        operation_text: operation.operation_text,
        auto_inserted: operation.auto_inserted?
      }
    end
  end

  # ENP Strip Mask (unchanged)
  def has_enp_strip_mask_operations?
    enp_ids = ['ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC', 'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL']
    (operation_selection["selected_operations"] || []).any? { |id| enp_ids.include?(id) }
  end

  private

  # Add single treatment cycle operations
  def add_treatment_cycle(sequence, treatment, has_enp)
    op = treatment[:operation]
    treatment_data = treatment[:treatment_data]
    masking = treatment[:masking]
    stripping = treatment[:stripping]
    sealing = treatment[:sealing]

    # ENP has special workflow - no masking/stripping modifiers
    if op.process_type == 'electroless_nickel_plating'
      add_enp_cycle(sequence, op, treatment_data)
      return
    end

    # Standard anodising/chemical conversion cycle
    # 1. Masking
    if masking["enabled"] && masking["methods"].present?
      sequence << OperationLibrary::Masking.get_masking_operation(masking["methods"])
      sequence << OperationLibrary::Masking.get_masking_inspection_operation
    end

    # 2. Jig
    sequence << OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)

    # 3. Degrease + rinse
    if needs_degrease?(op)
      degrease = OperationLibrary::DegreaseOperations.get_degrease_operation
      sequence << degrease
      sequence << get_rinse(degrease, has_enp)
    end

    # 4. Pretreatments + rinses
    if needs_pretreatment?(op)
      pretreatments = OperationLibrary::Pretreatments.get_pretreatment_sequence([op], nil)
      pretreatments.each do |pretreat|
        sequence << pretreat
        sequence << get_rinse(pretreat, has_enp) unless pretreat.process_type == 'rinse'
      end
    end

    # 5. Stripping + rinse
    if stripping["enabled"] && stripping["type"].present? && stripping["method"].present?
      strip_op = OperationLibrary::Stripping.get_stripping_operation(stripping["type"], stripping["method"])
      sequence << strip_op
      sequence << get_rinse(strip_op, has_enp)
    end

    # 6. Main operation + rinse
    sequence << op
    sequence << get_rinse(op, has_enp)

    # 7. Sealing + rinse
    if sealing["enabled"] && sealing["type"].present? && is_anodising?(op)
      seal_op = OperationLibrary::Sealing.get_sealing_operation(sealing["type"])
      if seal_op
        sequence << seal_op
        sequence << get_rinse(seal_op, has_enp)
      end
    end

    # 8. Unjig
    sequence << OperationLibrary::JigUnjig.get_unjig_operation

    # 9. Masking removal
    if masking["enabled"] && masking["methods"].present?
      if OperationLibrary::Masking.masking_removal_required?([], masking["methods"])
        sequence.concat(OperationLibrary::Masking.get_masking_removal_operations)
      end
    end
  end

  # ENP special cycle - jig, degrease, pretreat, plate, unjig (masking happens later via ENP Strip Mask)
  def add_enp_cycle(sequence, enp_op, treatment_data)
    # 1. Jig
    sequence << OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)

    # 2. Degrease + rinse
    degrease = OperationLibrary::DegreaseOperations.get_degrease_operation
    sequence << degrease
    sequence << get_rinse(degrease, true)

    # 3. ENP pretreatments + rinses
    if defined?(OperationLibrary::Pretreatments)
      # Get the selected alloy for the ENP treatment from the treatment data
      selected_alloy = get_selected_enp_alloy_for_treatment_data(treatment_data)
      if selected_alloy
        pretreatments = OperationLibrary::Pretreatments.get_pretreatment_sequence([enp_op], selected_alloy)
        pretreatments.each do |pretreat|
          sequence << pretreat
          sequence << get_rinse(pretreat, true) unless pretreat.process_type == 'rinse'
        end
      end
    end

    # 4. ENP operation + rinse
    sequence << enp_op
    sequence << get_rinse(enp_op, true)

    # 5. Unjig
    sequence << OperationLibrary::JigUnjig.get_unjig_operation
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

  def get_rinse(op, has_enp)
    OperationLibrary::RinseOperations.get_rinse_operation(op, ppi_contains_electroless_nickel: has_enp)
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
end
