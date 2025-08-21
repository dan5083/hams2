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

  # Get operations with auto-inserted operations (rinses, pre-treatments, etc.)
  def get_operations_with_auto_ops
    user_operations = get_operations
    return [] if user_operations.empty?

    operations_with_auto_ops = []
    has_special_requirements = has_special_auto_op_requirements?

    user_operations.each do |operation|
      # Add the user operation
      operations_with_auto_ops << operation

      # Add auto-operations after this operation if it requires them
      auto_ops = get_auto_operations_after(operation, has_special_requirements)
      operations_with_auto_ops.concat(auto_ops)
    end

    operations_with_auto_ops
  end

  # Check if this PPI has special auto-operation requirements (electroless nickel plating, etc.)
  def has_special_auto_op_requirements?
    selected_operations.any? do |op_id|
      operation = Operation.all_operations.find { |op| op.id == op_id }
      operation&.process_type == 'electroless_nickel_plating'
    end
  end

  # Get auto-operations that should be inserted after a given operation
  def get_auto_operations_after(operation, has_special_requirements = false)
    auto_ops = []

    # Add rinse operations (first type of auto-operation)
    if OperationLibrary::RinseOperations.operation_requires_rinse?(operation)
      rinse_operation = OperationLibrary::RinseOperations.get_rinse_operation(
        operation,
        ppi_contains_electroless_nickel: has_special_requirements
      )
      auto_ops << rinse_operation if rinse_operation
    end

    # Future auto-operations can be added here:
    # - Drying operations
    # - Quality checks
    # - Pre-treatments
    # - etc.

    auto_ops
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
  def self.simulate_operations_with_auto_ops(operation_ids)
    return [] if operation_ids.blank?

    all_ops = Operation.all_operations
    user_operations = operation_ids.map do |op_id|
      all_ops.find { |op| op.id == op_id }
    end.compact

    return [] if user_operations.empty?

    # Build operations with auto-ops for preview
    operations_with_auto_ops = []
    has_special_requirements = user_operations.any? { |op| op.process_type == 'electroless_nickel_plating' }

    user_operations.each do |operation|
      # Add the user operation
      operations_with_auto_ops << {
        id: operation.id,
        display_name: operation.display_name,
        operation_text: operation.operation_text,
        auto_inserted: false
      }

      # Add auto-operations after this operation
      # For now, just rinse operations, but extensible for future auto-ops
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

      # Future auto-operations can be added here
    end

    operations_with_auto_ops
  end

  # Legacy method for summary text (keep for compatibility)
  def self.simulate_operations_summary(operation_ids)
    operations_with_auto_ops = simulate_operations_with_auto_ops(operation_ids)
    return "No operations selected" if operations_with_auto_ops.empty?

    operations_with_auto_ops.map { |op| op[:display_name] }.join(" → ")
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

    if selected_operations.length > 3
      errors.add(:base, "cannot select more than 3 operations")
    end

    all_op_ids = Operation.all_operations.map(&:id)
    invalid_ids = selected_operations - all_op_ids
    if invalid_ids.any?
      errors.add(:base, "contains invalid operation IDs: #{invalid_ids.join(', ')}")
    end
  end
end
