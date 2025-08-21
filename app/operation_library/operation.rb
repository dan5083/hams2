# app/operation_library/operation.rb
class Operation
  attr_accessor :id, :alloys, :process_type, :anodic_classes, :target_thickness, :vat_numbers, :operation_text, :specifications

  def initialize(id:, process_type:, operation_text:, specifications: nil, alloys: [], anodic_classes: [], target_thickness: 0, vat_numbers: [])
    @id = id
    @alloys = alloys
    @process_type = process_type
    @anodic_classes = anodic_classes
    @target_thickness = target_thickness
    @vat_numbers = vat_numbers
    @operation_text = operation_text
    @specifications = specifications
  end

  # Class methods to get all operations from all files
  def self.all_operations
    @all_operations ||= load_all_operations
  end

  def self.load_all_operations
    operations = []
    operations += OperationLibrary::AnodisingStandard.operations if defined?(OperationLibrary::AnodisingStandard)
    operations += OperationLibrary::AnodisingHard.operations if defined?(OperationLibrary::AnodisingHard)
    operations += OperationLibrary::AnodisingChromic.operations if defined?(OperationLibrary::AnodisingChromic)
    operations += OperationLibrary::ChemicalConversions.operations if defined?(OperationLibrary::ChemicalConversions)
    operations += OperationLibrary::RinseOperations.operations if defined?(OperationLibrary::RinseOperations)
    operations
  end

  # Filter operations by criteria (excluding rinse operations from normal filtering)
  def self.find_matching(process_type: nil, alloy: nil, target_thickness: nil, anodic_class: nil)
    matching = all_operations.reject { |op| op.process_type == 'rinse' } # Exclude rinses from normal filtering

    matching = matching.select { |op| op.process_type == process_type } if process_type.present?
    matching = matching.select { |op| op.alloys.include?(alloy) } if alloy.present?
    matching = matching.select { |op| op.anodic_classes.include?(anodic_class) } if anodic_class.present?

    # For thickness, find operations that match exactly or are close
    if target_thickness.present?
      target = target_thickness.to_f
      matching = matching.select do |op|
        # Exact match or within reasonable tolerance (±2.5μm)
        (op.target_thickness - target).abs <= 2.5
      end
      # Sort by closest thickness match first
      matching = matching.sort_by { |op| (op.target_thickness - target).abs }
    end

    matching
  end

  # Get available options for dropdowns (excluding rinse operations)
  def self.available_process_types
    all_operations.reject { |op| op.process_type == 'rinse' }.map(&:process_type).uniq.sort
  end

  def self.available_alloys
    all_operations.reject { |op| op.process_type == 'rinse' }.flat_map(&:alloys).uniq.sort
  end

  def self.available_anodic_classes
    all_operations.reject { |op| op.process_type == 'rinse' }.flat_map(&:anodic_classes).uniq.sort
  end

  def self.available_thicknesses
    all_operations.reject { |op| op.process_type == 'rinse' }.map(&:target_thickness).uniq.select { |t| t > 0 }.sort
  end

  # Get rinse operations specifically
  def self.rinse_operations
    all_operations.select { |op| op.process_type == 'rinse' }
  end

  # Instance methods
  def display_name
    if process_type == 'rinse'
      case id
      when 'CASCADE_RINSE'
        'Cascade Rinse'
      when 'RO_RINSE'
        'RO Rinse'
      else
        'Rinse'
      end
    elsif target_thickness > 0
      "#{id} (#{target_thickness}μm)"
    else
      id.humanize
    end
  end

  def vat_options_text
    if vat_numbers.length == 1
      "Vat #{vat_numbers.first}"
    else
      "Vats #{vat_numbers.join(', ')}"
    end
  end

  def matches_criteria?(process_type: nil, alloy: nil, target_thickness: nil, anodic_class: nil)
    return false if process_type.present? && self.process_type != process_type
    return false if alloy.present? && !alloys.include?(alloy)
    return false if anodic_class.present? && !anodic_classes.include?(anodic_class)

    if target_thickness.present?
      target = target_thickness.to_f
      return false if (self.target_thickness - target).abs > 2.5
    end

    true
  end

  def to_hash
    {
      id: id,
      alloys: alloys,
      process_type: process_type,
      anodic_classes: anodic_classes,
      target_thickness: target_thickness,
      vat_numbers: vat_numbers,
      operation_text: operation_text,
      specifications: specifications
    }
  end

  # Check if this operation is a rinse
  def rinse?
    process_type == 'rinse'
  end

  # Check if this operation is auto-inserted (rinse operations are auto-inserted)
  def auto_inserted?
    rinse?
  end
end
