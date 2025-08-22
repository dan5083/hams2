# app/operation_library/operation.rb - Updated to handle degrease operations
class Operation
  attr_accessor :id, :alloys, :process_type, :anodic_classes, :target_thickness, :vat_numbers,
                :operation_text, :specifications, :enp_type, :deposition_rate_range, :time

  def initialize(id:, process_type:, operation_text:, specifications: nil, alloys: [],
                 anodic_classes: [], target_thickness: 0, vat_numbers: [],
                 enp_type: nil, deposition_rate_range: nil, time: nil)
    @id = id
    @alloys = alloys
    @process_type = process_type
    @anodic_classes = anodic_classes
    @target_thickness = target_thickness
    @vat_numbers = vat_numbers
    @operation_text = operation_text
    @specifications = specifications
    @enp_type = enp_type
    @deposition_rate_range = deposition_rate_range
    @time = time
  end

  # Class methods to get all operations from all files
  def self.all_operations(target_thickness = nil)
    # Don't memoize when thickness is provided (ENP needs fresh interpolation)
    if target_thickness.present?
      load_all_operations(target_thickness)
    else
      @all_operations ||= load_all_operations(nil)
    end
  end

  def self.load_all_operations(target_thickness = nil)
    operations = []
    operations += OperationLibrary::DegreaseOperations.operations if defined?(OperationLibrary::DegreaseOperations)
    operations += OperationLibrary::AnodisingStandard.operations if defined?(OperationLibrary::AnodisingStandard)
    operations += OperationLibrary::AnodisingHard.operations if defined?(OperationLibrary::AnodisingHard)
    operations += OperationLibrary::AnodisingChromic.operations if defined?(OperationLibrary::AnodisingChromic)
    operations += OperationLibrary::ChemicalConversions.operations if defined?(OperationLibrary::ChemicalConversions)

    # Pass thickness to ENP operations for time interpolation
    if defined?(OperationLibrary::ElectrolessNickelPlate)
      operations += OperationLibrary::ElectrolessNickelPlate.operations(target_thickness)
    end

    operations += OperationLibrary::RinseOperations.operations if defined?(OperationLibrary::RinseOperations)
    operations
  end

  # Filter operations by criteria (excluding rinse and degrease operations from normal filtering)
  def self.find_matching(process_type: nil, alloy: nil, target_thickness: nil, anodic_class: nil, enp_type: nil)
    matching = all_operations(target_thickness).reject { |op| op.process_type == 'rinse' || op.process_type == 'degrease' }

    matching = matching.select { |op| op.process_type == process_type } if process_type.present?
    matching = matching.select { |op| op.alloys.include?(alloy) } if alloy.present?
    matching = matching.select { |op| op.anodic_classes.include?(anodic_class) } if anodic_class.present?
    matching = matching.select { |op| op.enp_type == enp_type } if enp_type.present?

    # For thickness, find operations that match exactly or are close (skip for ENP and chemical conversion)
    if target_thickness.present?
      target = target_thickness.to_f
      matching = matching.select do |op|
        # Skip thickness filtering for electroless nickel plating and chemical conversion
        if op.process_type == 'electroless_nickel_plating' || op.process_type == 'chemical_conversion'
          true
        else
          # Exact match or within reasonable tolerance (±2.5μm)
          (op.target_thickness - target).abs <= 2.5
        end
      end
      # Sort by closest thickness match (but only for non-ENP/chemical conversion)
      matching = matching.sort_by do |op|
        if op.process_type == 'electroless_nickel_plating' || op.process_type == 'chemical_conversion'
          0
        else
          (op.target_thickness - target).abs
        end
      end
    end

    matching
  end

  # Get available options for dropdowns (excluding rinse and degrease operations)
  def self.available_process_types
    all_operations.reject { |op| op.process_type == 'rinse' || op.process_type == 'degrease' }.map(&:process_type).uniq.sort
  end

  def self.available_alloys
    all_operations.reject { |op| op.process_type == 'rinse' || op.process_type == 'degrease' }.flat_map(&:alloys).uniq.sort
  end

  def self.available_anodic_classes
    all_operations.reject { |op| op.process_type == 'rinse' || op.process_type == 'degrease' }.flat_map(&:anodic_classes).uniq.sort
  end

  def self.available_thicknesses
    all_operations.reject { |op| op.process_type == 'rinse' || op.process_type == 'degrease' }.map(&:target_thickness).uniq.select { |t| t > 0 }.sort
  end

  def self.available_enp_types
    all_operations.select { |op| op.process_type == 'electroless_nickel_plating' }.map(&:enp_type).uniq.compact.sort
  end

  # Get specific operation types
  def self.rinse_operations
    all_operations.select { |op| op.process_type == 'rinse' }
  end

  def self.degrease_operations
    all_operations.select { |op| op.process_type == 'degrease' }
  end

  def self.electroless_nickel_operations
    all_operations.select { |op| op.process_type == 'electroless_nickel_plating' }
  end

  # Instance methods
  def display_name
    if process_type == 'degrease'
      'Degrease'
    elsif process_type == 'rinse'
      case id
      when 'CASCADE_RINSE'
        'Cascade Rinse'
      when 'RO_RINSE'
        'RO Rinse'
      else
        'Rinse'
      end
    elsif process_type == 'electroless_nickel_plating'
      case enp_type
      when 'high_phosphorous'
        'High Phos ENP'
      when 'medium_phosphorous'
        'Medium Phos ENP'
      when 'low_phosphorous'
        'Low Phos ENP'
      when 'ptfe_composite'
        'PTFE Composite ENP'
      else
        'Electroless Nickel'
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
    elsif vat_numbers.length > 1
      "Vats #{vat_numbers.join(', ')}"
    else
      "" # No vat specified (e.g., for degrease operations)
    end
  end

  def matches_criteria?(process_type: nil, alloy: nil, target_thickness: nil, anodic_class: nil, enp_type: nil)
    return false if process_type.present? && self.process_type != process_type
    return false if alloy.present? && !alloys.include?(alloy)
    return false if anodic_class.present? && !anodic_classes.include?(anodic_class)
    return false if enp_type.present? && self.enp_type != enp_type

    if target_thickness.present? && self.process_type != 'electroless_nickel_plating' && self.process_type != 'chemical_conversion'
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
      specifications: specifications,
      enp_type: enp_type,
      deposition_rate_range: deposition_rate_range,
      time: time
    }
  end

  # Check operation types
  def degrease?
    process_type == 'degrease'
  end

  def rinse?
    process_type == 'rinse'
  end

  def electroless_nickel_plating?
    process_type == 'electroless_nickel_plating'
  end

  # Check if this operation is auto-inserted (rinse and degrease operations are auto-inserted)
  def auto_inserted?
    rinse? || degrease?
  end

  # Calculate plating time for ENP operations
  def calculate_plating_time(target_thickness_um)
    return nil unless electroless_nickel_plating? && deposition_rate_range

    OperationLibrary::ElectrolessNickelPlate.calculate_plating_time(id, target_thickness_um)
  end
end
