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
  validates :selected_operations, presence: true, if: :has_operation_selection?
  validate :validate_selected_operations

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :for_part_number, ->(part_number) { where("part_number ILIKE ?", "%#{part_number}%") }
  scope :for_part_issue, ->(part_issue) { where("part_issue ILIKE ?", "%#{part_issue}%") }

  before_validation :set_part_from_details, if: :part_details_changed?
  before_validation :build_specification_from_operations, if: :selected_operations_changed?
  after_initialize :set_defaults, if: :new_record?
  after_create :disable_replaced_ppi

  def self.create_from_data(data, user = nil)
    part = Part.ensure(
      customer_id: data[:customer_id],
      part_number: data[:part_number],
      part_issue: data[:part_issue]
    )

    ppi = new(data.merge(part: part))
    ppi.save!
    ppi
  end

  def self.search(customer_id: nil, part_number: nil, part_issue: nil, only_enabled: true)
    scope = all
    scope = scope.for_customer(customer_id) if customer_id
    scope = scope.for_part_number(part_number) if part_number
    scope = scope.for_part_issue(part_issue) if part_issue
    scope = scope.enabled if only_enabled
    scope
  end

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

  def build_customised_process
    return {} unless process_type.present? && customisation_data.present?
    ProcessBuilder.build_process(process_type, customisation_data, part: part)
  end

  def process_builder
    @process_builder ||= ProcessBuilder.for_type(process_type)
  end

  def available_customizations
    process_builder&.available_customizations || {}
  end

  def active?
    enabled && part&.enabled && customer&.active?
  end

  # Get selected operations (user-chosen operations only)
  def get_operations
    ops = selected_operations # This now handles JSON string parsing
    return [] unless ops.present?

    all_ops = Operation.all_operations
    ops.map do |op_id|
      all_ops.find { |op| op.id == op_id }
    end.compact
  end

  # Get operations with auto-inserted operations (inspections, jigs, rinses, etc.)
  def get_operations_with_auto_ops
    user_operations = get_operations
    return [] if user_operations.empty?

    operations_with_auto_ops = []
    has_special_requirements = has_special_auto_op_requirements?
    has_masking = selected_operations.include?('MASKING')

    # 1. Auto-insert contract review at the very beginning (always required)
    if OperationLibrary::ContractReviewOperations.contract_review_required?(user_operations)
      contract_review_operation = OperationLibrary::ContractReviewOperations.get_contract_review_operation
      operations_with_auto_ops << contract_review_operation
    end

    # 2. Auto-insert incoming inspection after contract review
    if OperationLibrary::InspectFinalInspectVatInspect.incoming_inspection_required?(user_operations)
      incoming_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_incoming_inspection_operation
      operations_with_auto_ops << incoming_inspection_operation
    end

    # 3. Auto-insert VAT inspection before degrease
    if OperationLibrary::InspectFinalInspectVatInspect.vat_inspection_required?(user_operations)
      vat_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_vat_inspection_operation
      operations_with_auto_ops << vat_inspection_operation
    end

    # 4. MODIFIED: Check if masking is present - if so, handle masking first, then jig
    if has_masking
      # 4a. Add masking operation first (for anodising treatments)
      masking_operation = build_final_operation(user_operations.find { |op| op.process_type == 'masking' })
      operations_with_auto_ops << masking_operation if masking_operation

      # 4b. Then add jig operation after masking
      if OperationLibrary::JigUnjig.jigging_required?(user_operations)
        jig_operation = OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)
        operations_with_auto_ops << jig_operation
      end
    else
      # 4c. Original logic: jig before degrease when no masking
      if OperationLibrary::JigUnjig.jigging_required?(user_operations)
        jig_operation = OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)
        operations_with_auto_ops << jig_operation
      end
    end

    # 5. Auto-insert degrease after jig if needed for surface treatments
    if OperationLibrary::DegreaseOperations.degreasing_required?(user_operations)
      degrease_operation = OperationLibrary::DegreaseOperations.get_degrease_operation
      operations_with_auto_ops << degrease_operation
    end

    # 6. Add remaining user operations (excluding masking which was handled above)
    user_operations_without_masking = user_operations.reject { |op| op.process_type == 'masking' }

    user_operations_without_masking.each_with_index do |operation, index|
      # Add the user operation with interpolated text
      final_operation = build_final_operation(operation)
      operations_with_auto_ops << final_operation

      # Add rinse operations after chemical processes
      if OperationLibrary::RinseOperations.operation_requires_rinse?(operation)
        rinse_operation = OperationLibrary::RinseOperations.get_rinse_operation(
          operation,
          ppi_contains_electroless_nickel: has_special_requirements
        )
        if rinse_operation
          operations_with_auto_ops << rinse_operation
        end
      end
    end

    # 7. Auto-insert unjig before ENP Strip Mask operations
    if OperationLibrary::JigUnjig.unjigging_required?(user_operations)
      unjig_operation = OperationLibrary::JigUnjig.get_unjig_operation
      operations_with_auto_ops << unjig_operation
    end

    # 7.5. Auto-insert masking removal operations before final inspection (tape/lacquer only)
    if OperationLibrary::Masking.masking_removal_required?(selected_operations, selected_masking_methods)
      masking_removal_ops = OperationLibrary::Masking.get_masking_removal_operations
      operations_with_auto_ops += masking_removal_ops
    end

    # 7.75. Add ENP Strip Mask operations after unjig
    if has_enp_strip_mask_operations?
      enp_strip_operations = get_enp_strip_mask_operations_for_sequence
      operations_with_auto_ops += enp_strip_operations
    end

    # 8. Auto-insert final inspection before pack
    if OperationLibrary::InspectFinalInspectVatInspect.final_inspection_required?(user_operations)
      final_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_final_inspection_operation
      operations_with_auto_ops << final_inspection_operation
    end

    # 9. Auto-insert pack at the very end (always required)
    if OperationLibrary::PackOperations.pack_required?(operations_with_auto_ops)
      pack_operation = OperationLibrary::PackOperations.get_pack_operation
      operations_with_auto_ops << pack_operation
    end

    operations_with_auto_ops
  end

  # Build final operation with interpolations for masking and stripping
  def build_final_operation(operation)
    case operation.process_type
    when 'masking'
      # Build masking operation with selected methods and locations
      masking_methods = selected_masking_methods
      OperationLibrary::Masking.get_masking_operation(masking_methods)
    when 'stripping'
      # Build stripping operation with selected type and method
      stripping_type = selected_stripping_type
      stripping_method = selected_stripping_method
      OperationLibrary::Stripping.get_stripping_operation(stripping_type, stripping_method)
    else
      # Return operation as-is for other types
      operation
    end
  end

  # Check if this PPI has special auto-operation requirements (electroless nickel plating, etc.)
  def has_special_auto_op_requirements?
    selected_operations.any? do |op_id|
      operation = Operation.all_operations.find { |op| op.id == op_id }
      operation&.process_type == 'electroless_nickel_plating'
    end
  end

  # Check if ENP Strip Mask operations are selected
  def has_enp_strip_mask_operations?
    enp_strip_mask_ids = [
      'ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'
    ]
    selected_operations.any? { |op_id| enp_strip_mask_ids.include?(op_id) }
  end

  # Get ENP Strip Mask operations for insertion into sequence
  def get_enp_strip_mask_operations_for_sequence
    return [] unless has_enp_strip_mask_operations? && defined?(OperationLibrary::EnpStripMask)

    strip_type = selected_enp_strip_type || 'nitric'
    OperationLibrary::EnpStripMask.operations(strip_type)
  end

  # Get the selected jig type for interpolation
  def selected_jig_type
    operation_selection["selected_jig_type"]
  end

  # Get the selected ENP strip type
  def selected_enp_strip_type
    operation_selection["enp_strip_type"] || 'nitric'
  end

  # Set the ENP strip type
  def selected_enp_strip_type=(strip_type)
    operation_selection["enp_strip_type"] = strip_type
  end

  # Masking methods and locations
  def selected_masking_methods
    masking_data = operation_selection["masking_methods"] || {}
    # Filter out empty values and return hash of method => location
    masking_data.select { |method, location| method.present? }
  end

  def selected_masking_methods=(methods_hash)
    operation_selection["masking_methods"] = methods_hash || {}
  end

  # Stripping type and method
  def selected_stripping_type
    operation_selection["stripping_type"]
  end

  def selected_stripping_type=(type)
    operation_selection["stripping_type"] = type
  end

  def selected_stripping_method
    operation_selection["stripping_method"]
  end

  def selected_stripping_method=(method)
    operation_selection["stripping_method"] = method
  end

  def operation_selection
    customisation_data["operation_selection"] || {}
  end

  def operation_selection=(data)
    customisation_data["operation_selection"] = data
  end

  def anodising_types
    operation_selection["anodising_types"] || []
  end

  def alloys
    operation_selection["alloys"] || []
  end

  def target_thicknesses
    operation_selection["target_thicknesses"] || []
  end

  def anodic_classes
    operation_selection["anodic_classes"] || []
  end

  def selected_operations
    ops = operation_selection["selected_operations"] || []
    # Handle case where it might be stored as a JSON string
    if ops.is_a?(String)
      begin
        ops = JSON.parse(ops)
      rescue JSON::ParserError
        ops = []
      end
    end
    ops
  end

  # Operations text with auto-inserted operations
  def operations_text
    get_operations_with_auto_ops.map.with_index(1) do |operation, index|
      "Operation #{index}: #{operation.operation_text}"
    end.join("\n\n")
  end

  # Build route card operations with auto-inserted operations
  def build_route_card_operations
    # Get operations with auto-ops included
    operations_with_auto_ops = get_operations_with_auto_ops

    # Create separate operation for each operation (including auto-inserted ones)
    operations_with_auto_ops.map.with_index do |operation, index|
      {
        number: index + 1,
        content: [{
          type: 'paragraph',
          as_html: operation.operation_text
        }],
        all_variables: [],
        auto_inserted: operation.auto_inserted? # Mark auto-inserted operations
      }
    end
  end

  # Operations summary with auto-inserted operations
  def operations_summary
    operations_with_auto_ops = get_operations_with_auto_ops
    return "No operations selected" if operations_with_auto_ops.empty?

    operations_with_auto_ops.map(&:display_name).join(" → ")
  end

  # Class method for real-time simulation during PPI building
  # Returns detailed operation data for form preview (including auto-operations)
  def self.simulate_operations_with_auto_ops(operation_ids, target_thickness = nil, selected_jig_type = nil, enp_strip_type = 'nitric', masking_methods = {}, stripping_type = nil, stripping_method = nil)
    return [] if operation_ids.blank?

    # Get operations with thickness for ENP interpolation
    all_ops = Operation.all_operations(target_thickness)

    # Add ENP Strip Mask operations if needed
    if defined?(OperationLibrary::EnpStripMask)
      all_ops += OperationLibrary::EnpStripMask.operations('nitric')
      all_ops += OperationLibrary::EnpStripMask.operations('metex_dekote')
    end

    # Add masking and stripping operations
    if masking_methods.present?
      masking_op = OperationLibrary::Masking.get_masking_operation(masking_methods)
      all_ops << masking_op
    else
      # Add placeholder masking operation
      all_ops << OperationLibrary::Masking.get_masking_operation({})
    end

    if stripping_type.present?
      stripping_op = OperationLibrary::Stripping.get_stripping_operation(stripping_type, stripping_method)
      all_ops << stripping_op
    else
      # Add placeholder stripping operation
      all_ops << OperationLibrary::Stripping.get_stripping_operation(nil, nil)
    end

    # Expand ENP Strip Mask operations and filter to selected ones
    expanded_operation_ids = expand_enp_strip_mask_operations(operation_ids, enp_strip_type)
    user_operations = expanded_operation_ids.map do |op_id|
      all_ops.find { |op| op.id == op_id }
    end.compact

    return [] if user_operations.empty?

    operations_with_auto_ops = []
    has_special_requirements = user_operations.any? { |op| op.process_type == 'electroless_nickel_plating' }
    has_enp_strip_mask = user_operations.any? { |op| ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type) }
    has_masking = operation_ids.include?('MASKING')

    # 1. Contract review
    if OperationLibrary::ContractReviewOperations.contract_review_required?(user_operations)
      contract_review_operation = OperationLibrary::ContractReviewOperations.get_contract_review_operation
      operations_with_auto_ops << {
        id: contract_review_operation.id,
        display_name: contract_review_operation.display_name,
        operation_text: contract_review_operation.operation_text,
        auto_inserted: true
      }
    end

    # 2. Incoming inspection
    if OperationLibrary::InspectFinalInspectVatInspect.incoming_inspection_required?(user_operations)
      incoming_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_incoming_inspection_operation
      operations_with_auto_ops << {
        id: incoming_inspection_operation.id,
        display_name: incoming_inspection_operation.display_name,
        operation_text: incoming_inspection_operation.operation_text,
        auto_inserted: true
      }
    end

    # 3. VAT inspection
    if OperationLibrary::InspectFinalInspectVatInspect.vat_inspection_required?(user_operations)
      vat_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_vat_inspection_operation
      operations_with_auto_ops << {
        id: vat_inspection_operation.id,
        display_name: vat_inspection_operation.display_name,
        operation_text: vat_inspection_operation.operation_text,
        auto_inserted: true
      }
    end

    # 4. MODIFIED: Handle masking first, then jig if masking is present
    if has_masking
      # 4a. Add masking operation first
      masking_operation = user_operations.find { |op| op.process_type == 'masking' }
      if masking_operation
        masking_op = OperationLibrary::Masking.get_masking_operation(masking_methods)
        operations_with_auto_ops << {
          id: masking_op.id,
          display_name: masking_op.display_name,
          operation_text: masking_op.operation_text,
          auto_inserted: false
        }
      end

      # 4b. Then add jig operation after masking
      if OperationLibrary::JigUnjig.jigging_required?(user_operations)
        jig_operation = OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)
        operations_with_auto_ops << {
          id: jig_operation.id,
          display_name: jig_operation.display_name,
          operation_text: jig_operation.operation_text,
          auto_inserted: true
        }
      end
    else
      # 4c. Original logic: jig before degrease when no masking
      if OperationLibrary::JigUnjig.jigging_required?(user_operations)
        jig_operation = OperationLibrary::JigUnjig.get_jig_operation(selected_jig_type)
        operations_with_auto_ops << {
          id: jig_operation.id,
          display_name: jig_operation.display_name,
          operation_text: jig_operation.operation_text,
          auto_inserted: true
        }
      end
    end

    # 5. Degrease
    if OperationLibrary::DegreaseOperations.degreasing_required?(user_operations)
      degrease_operation = OperationLibrary::DegreaseOperations.get_degrease_operation
      operations_with_auto_ops << {
        id: degrease_operation.id,
        display_name: degrease_operation.display_name,
        operation_text: degrease_operation.operation_text,
        auto_inserted: true
      }
    end

    # 6. User operations (excluding masking which was handled above)
    user_operations_without_enp_strip = user_operations.reject { |op| ['mask', 'masking_check', 'strip', 'strip_masking', 'masking'].include?(op.process_type) }
    enp_strip_operations = user_operations.select { |op| ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type) }

    user_operations_without_enp_strip.each do |operation|
      # Handle special interpolation for stripping (masking was handled above)
      final_op_data = case operation.process_type
      when 'stripping'
        stripping_op = OperationLibrary::Stripping.get_stripping_operation(stripping_type, stripping_method)
        {
          id: stripping_op.id,
          display_name: stripping_op.display_name,
          operation_text: stripping_op.operation_text,
          auto_inserted: false
        }
      else
        {
          id: operation.id,
          display_name: operation.display_name,
          operation_text: operation.operation_text,
          auto_inserted: false
        }
      end

      operations_with_auto_ops << final_op_data

      # Add rinse operations
      if OperationLibrary::RinseOperations.operation_requires_rinse?(operation)
        rinse_operation = OperationLibrary::RinseOperations.get_rinse_operation(
          operation,
          ppi_contains_electroless_nickel: has_special_requirements
        )
        if rinse_operation
          operations_with_auto_ops << {
            id: rinse_operation.id,
            display_name: rinse_operation.display_name,
            operation_text: rinse_operation.operation_text,
            auto_inserted: true
          }
        end
      end
    end

    # 7. Unjig
    if OperationLibrary::JigUnjig.unjigging_required?(user_operations)
      unjig_operation = OperationLibrary::JigUnjig.get_unjig_operation
      operations_with_auto_ops << {
        id: unjig_operation.id,
        display_name: unjig_operation.display_name,
        operation_text: unjig_operation.operation_text,
        auto_inserted: true
      }
    end

    # 7.5. Masking removal operations (tape/lacquer only)
    if OperationLibrary::Masking.masking_removal_required?(expanded_operation_ids, masking_methods)
      masking_removal_ops = OperationLibrary::Masking.get_masking_removal_operations
      masking_removal_ops.each do |masking_removal_op|
        operations_with_auto_ops << {
          id: masking_removal_op.id,
          display_name: masking_removal_op.display_name,
          operation_text: masking_removal_op.operation_text,
          auto_inserted: true
        }
      end
    end

    # 7.75. ENP Strip Mask operations
    if has_enp_strip_mask
      enp_strip_operations.each do |enp_strip_op|
        operations_with_auto_ops << {
          id: enp_strip_op.id,
          display_name: enp_strip_op.display_name,
          operation_text: enp_strip_op.operation_text,
          auto_inserted: false
        }
      end
    end

    # 8. Final inspection
    if OperationLibrary::InspectFinalInspectVatInspect.final_inspection_required?(user_operations)
      final_inspection_operation = OperationLibrary::InspectFinalInspectVatInspect.get_final_inspection_operation
      operations_with_auto_ops << {
        id: final_inspection_operation.id,
        display_name: final_inspection_operation.display_name,
        operation_text: final_inspection_operation.operation_text,
        auto_inserted: true
      }
    end

    # 9. Pack
    if OperationLibrary::PackOperations.pack_required?(operations_with_auto_ops.map { |op| OpenStruct.new(process_type: op[:id] == 'PACK' ? 'pack' : 'other') })
      pack_operation = OperationLibrary::PackOperations.get_pack_operation
      operations_with_auto_ops << {
        id: pack_operation.id,
        display_name: pack_operation.display_name,
        operation_text: pack_operation.operation_text,
        auto_inserted: true
      }
    end

    operations_with_auto_ops
  end

  # Update simulation summary to accept new parameters
  def self.simulate_operations_summary(operation_ids, target_thickness = nil, selected_jig_type = nil, enp_strip_type = 'nitric', masking_methods = {}, stripping_type = nil, stripping_method = nil)
    operations_with_auto_ops = simulate_operations_with_auto_ops(operation_ids, target_thickness, selected_jig_type, enp_strip_type, masking_methods, stripping_type, stripping_method)
    return "No operations selected" if operations_with_auto_ops.empty?

    operations_with_auto_ops.map { |op| op[:display_name] }.join(" → ")
  end

  # Expand ENP Strip Mask operations to full sequence
  def self.expand_enp_strip_mask_operations(operation_ids, enp_strip_type)
    return operation_ids unless defined?(OperationLibrary::EnpStripMask)

    expanded_ids = []
    enp_strip_mask_ids = [
      'ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'
    ]

    operation_ids.each do |op_id|
      if enp_strip_mask_ids.include?(op_id)
        # Replace any ENP Strip Mask operation with the complete sequence
        unless expanded_ids.any? { |id| enp_strip_mask_ids.include?(id) }
          expanded_ids += OperationLibrary::EnpStripMask.get_operation_ids(enp_strip_type)
        end
      else
        expanded_ids << op_id
      end
    end

    expanded_ids
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.customisation_data = {} if customisation_data.blank?
  end

  def part_details_changed?
    part_number_changed? || part_issue_changed? || customer_id_changed?
  end

  def set_part_from_details
    return unless part_number.present? && part_issue.present? && customer_id.present?

    self.part = Part.ensure(
      customer_id: customer_id,
      part_number: part_number,
      part_issue: part_issue
    )
  end

  def disable_replaced_ppi
    return unless replaces_id.present?
    replaces&.disable!
  end

  def has_operation_selection?
    operation_selection.any?
  end

  def selected_operations_changed?
    customisation_data_changed? && customisation_data_change&.any? { |before, after|
      (before&.dig("operation_selection", "selected_operations") || []) != (after&.dig("operation_selection", "selected_operations") || [])
    }
  end

  def build_specification_from_operations
    return unless selected_operations.present?

    self.specification = operations_text
  end

  def validate_selected_operations
    return unless selected_operations.present?

    # Count non-ENP Strip Mask operations for the 5-operation limit
    enp_strip_mask_ids = [
      'ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'
    ]

    non_enp_strip_operations = selected_operations.reject { |op_id| enp_strip_mask_ids.include?(op_id) }

    if non_enp_strip_operations.length > 5
      errors.add(:base, "cannot select more than 5 main operations (ENP Strip Mask operations don't count toward this limit)")
    end

    all_op_ids = Operation.all_operations.map(&:id)
    # Add ENP Strip Mask operation IDs if available
    if defined?(OperationLibrary::EnpStripMask)
      all_op_ids += OperationLibrary::EnpStripMask.operations('nitric').map(&:id)
      all_op_ids += OperationLibrary::EnpStripMask.operations('metex_dekote').map(&:id)
    end

    # Add masking and stripping operation IDs
    all_op_ids += ['MASKING', 'STRIPPING']

    invalid_ids = selected_operations - all_op_ids
    if invalid_ids.any?
      errors.add(:base, "contains invalid operation IDs: #{invalid_ids.join(', ')}")
    end
  end
end
