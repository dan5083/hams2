# app/operation_library/operation.rb - Updated to handle pretreatments, ENP Strip Mask operations, masking removal, sealing, and water break test
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
    operations += OperationLibrary::ContractReviewOperations.operations if defined?(OperationLibrary::ContractReviewOperations)
    operations += OperationLibrary::InspectFinalInspectVatInspect.operations if defined?(OperationLibrary::InspectFinalInspectVatInspect)

    # Add pretreatments
    operations += OperationLibrary::Pretreatments.operations if defined?(OperationLibrary::Pretreatments)

    operations += OperationLibrary::JigUnjig.operations if defined?(OperationLibrary::JigUnjig)
    operations += OperationLibrary::DegreaseOperations.operations if defined?(OperationLibrary::DegreaseOperations)

    # Add water break test operations
    operations += OperationLibrary::WaterBreakOperations.operations if defined?(OperationLibrary::WaterBreakOperations)

    operations += OperationLibrary::AnodisingStandard.operations if defined?(OperationLibrary::AnodisingStandard)
    operations += OperationLibrary::AnodisingHard.operations if defined?(OperationLibrary::AnodisingHard)
    operations += OperationLibrary::AnodisingChromic.operations if defined?(OperationLibrary::AnodisingChromic)
    operations += OperationLibrary::ChemicalConversions.operations if defined?(OperationLibrary::ChemicalConversions)

    # Pass thickness to ENP operations for time interpolation
    if defined?(OperationLibrary::ElectrolessNickelPlate)
      operations += OperationLibrary::ElectrolessNickelPlate.operations(target_thickness)
    end

    # Add ENP Strip Mask operations (default to nitric strip type)
    if defined?(OperationLibrary::EnpStripMask)
      operations += OperationLibrary::EnpStripMask.operations('nitric')
      operations += OperationLibrary::EnpStripMask.operations('metex_dekote')
    end

    # Add sealing operations
    operations += OperationLibrary::Sealing.operations if defined?(OperationLibrary::Sealing)

    operations += OperationLibrary::RinseOperations.operations if defined?(OperationLibrary::RinseOperations)
    operations += OperationLibrary::PackOperations.operations if defined?(OperationLibrary::PackOperations)

    # Add masking operations (including removal operations)
    operations += OperationLibrary::Masking.operations if defined?(OperationLibrary::Masking)

    # Add stripping operations
    operations += OperationLibrary::Stripping.operations if defined?(OperationLibrary::Stripping)

    operations
  end

  # Filter operations by criteria (excluding auto-inserted operations from normal filtering)
  def self.find_matching(process_type: nil, alloy: nil, target_thickness: nil, anodic_class: nil, enp_type: nil)
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test']
    matching = all_operations(target_thickness).reject { |op| auto_inserted_types.include?(op.process_type) }

    matching = matching.select { |op| op.process_type == process_type } if process_type.present?
    matching = matching.select { |op| op.alloys.include?(alloy) } if alloy.present?
    matching = matching.select { |op| op.anodic_classes.include?(anodic_class) } if anodic_class.present?
    matching = matching.select { |op| op.enp_type == enp_type } if enp_type.present?

    # For thickness, find operations that match exactly or are close (skip for ENP, chemical conversion, masking, stripping, sealing, dichromate_sealing, and water_break_test)
    if target_thickness.present?
      target = target_thickness.to_f
      matching = matching.select do |op|
        # Skip thickness filtering for chemical conversion, ENP, masking, stripping, sealing, dichromate_sealing, water_break_test, and ENP Strip Mask
        if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'masking', 'stripping', 'sealing', 'dichromate_sealing', 'water_break_test']) ||
           ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type)
          true
        else
          # Exact match or within reasonable tolerance (±2.5μm)
          (op.target_thickness - target).abs <= 2.5
        end
      end
      # Sort by closest thickness match (but only for anodising operations)
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        matching = matching.sort_by do |op|
          if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'masking', 'stripping', 'sealing', 'dichromate_sealing', 'water_break_test']) ||
             ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type)
            0
          else
            (op.target_thickness - target).abs
          end
        end
      end
    end

    matching
  end

  # Get available options for dropdowns (excluding auto-inserted operations)
  def self.available_process_types
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.map(&:process_type).uniq.sort
  end

  def self.available_alloys
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.flat_map(&:alloys).uniq.sort
  end

  def self.available_anodic_classes
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.flat_map(&:anodic_classes).uniq.sort
  end

  def self.available_thicknesses
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.map(&:target_thickness).uniq.select { |t| t > 0 }.sort
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

  def self.pretreatment_operations
    all_operations.select { |op| ['pretreatment', 'enp_pretreatment'].include?(op.process_type) }
  end

  def self.inspection_operations
    all_operations.select { |op| ['inspect', 'vat_inspect', 'final_inspect'].include?(op.process_type) }
  end

  def self.jig_operations
    all_operations.select { |op| ['jig', 'unjig'].include?(op.process_type) }
  end

  def self.electroless_nickel_operations
    all_operations.select { |op| op.process_type == 'electroless_nickel_plating' }
  end

  def self.enp_strip_mask_operations
    all_operations.select { |op| ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type) }
  end

  def self.masking_operations
    all_operations.select { |op| ['masking', 'masking_removal', 'masking_removal_check', 'masking_inspection'].include?(op.process_type) }
  end

  def self.sealing_operations
    all_operations.select { |op| ['sealing', 'dichromate_sealing'].include?(op.process_type) }
  end

  def self.water_break_test_operations
    all_operations.select { |op| op.process_type == 'water_break_test' }
  end

  # Instance methods
  def display_name
    if process_type == 'contract_review'
      'Contract Review'
    elsif process_type == 'inspect'
      'Incoming Inspection'
    elsif process_type == 'vat_inspect'
      'VAT Inspection'
    elsif process_type == 'final_inspect'
      'Final Inspection'
    elsif process_type == 'water_break_test'
      'Water Break Test'
    elsif process_type == 'pretreatment'
      'DeOx Pretreatment'
    elsif process_type == 'enp_pretreatment'
      case id
      when /FERROUS_CLEANING/
        'Ferrous Cleaning'
      when /ELECTROCLEAN/
        'Electroclean'
      when /ACTIVATE/
        'Activation'
      when /WOODS_NICKEL/
        'Woods Nickel Strike'
      when /ALUMINIUM_CLEAN/
        'Aluminium Clean'
      when /DESMUT/
        'Desmut'
      when /ALUMON/
        'Alumon Treatment'
      when /ETCH_AWAY/
        'Strip Zincate'
      when /ZINCATE/
        'Zincate'
      when /PICKLING/
        'Pickling'
      when /ACID_DIP/
        'Acid Dip'
      when /ACID_ETCH/
        'Acid Etch'
      when /MICROETCH/
        'Microetch'
      else
        'ENP Pretreatment'
      end
    elsif process_type == 'jig'
      'Jig Parts'
    elsif process_type == 'unjig'
      'Unjig Parts'
    elsif process_type == 'degrease'
      'Degrease'
    elsif process_type == 'pack'
      'Pack'
    elsif process_type == 'masking_removal'
      'Masking Removal'
    elsif process_type == 'masking_removal_check'
      'Masking Removal Check'
    elsif process_type == 'masking_inspection'
      'Masking Inspection'
    elsif process_type == 'mask'
      'ENP Mask'
    elsif process_type == 'masking_check'
      'Masking Check'
    elsif process_type == 'strip'
      case id
      when 'ENP_STRIP_NITRIC'
        'ENP Strip (Nitric)'
      when 'ENP_STRIP_METEX'
        'ENP Strip (Metex)'
      else
        'Strip'
      end
    elsif process_type == 'strip_masking'
      'Strip Masking'
    elsif process_type == 'sealing' || process_type == 'dichromate_sealing'
      case id
      when 'SODIUM_DICHROMATE_SEAL'
        'Sodium Dichromate Seal'
      when 'OXIDITE_SECO_SEAL'
        'Oxidite SE-CO Seal'
      when 'HOT_WATER_DIP'
        'Hot Water Dip'
      when 'HOT_SEAL'
        'Hot Seal'
      when 'SURTEC_650V_SEAL'
        'SurTec 650V Seal'
      when 'DEIONISED_WATER_SEAL'
        'Deionised Water Seal'
      else
        'Sealing'
      end
    elsif process_type == 'rinse'
      case id
      when 'CASCADE_RINSE'
        'Cascade Rinse'
      when 'CASCADE_RINSE_BUNGS'
        'Cascade Rinse (Bungs)'
      when 'RO_RINSE'
        'RO Rinse'
      when 'RO_RINSE_PRETREATMENT'
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

    if target_thickness.present? && self.process_type != 'electroless_nickel_plating' &&
       self.process_type != 'chemical_conversion' &&
       !['mask', 'masking_check', 'strip', 'strip_masking', 'masking', 'stripping', 'sealing', 'dichromate_sealing', 'pretreatment', 'enp_pretreatment', 'water_break_test'].include?(self.process_type)
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
  def pretreatment?
    ['pretreatment', 'enp_pretreatment'].include?(process_type)
  end

  def degrease?
    process_type == 'degrease'
  end

  def water_break_test?
    process_type == 'water_break_test'
  end

  def rinse?
    process_type == 'rinse'
  end

  def inspection?
    ['inspect', 'vat_inspect', 'final_inspect'].include?(process_type)
  end

  def jig?
    process_type == 'jig'
  end

  def unjig?
    process_type == 'unjig'
  end

  def electroless_nickel_plating?
    process_type == 'electroless_nickel_plating'
  end

  def enp_strip_mask?
    ['mask', 'masking_check', 'strip', 'strip_masking'].include?(process_type)
  end

  def masking?
    process_type == 'masking'
  end

  def masking_removal?
    ['masking_removal', 'masking_removal_check'].include?(process_type)
  end

  def masking_inspection?
    process_type == 'masking_inspection'
  end

  def stripping?
    process_type == 'stripping'
  end

  def sealing?
    ['sealing', 'dichromate_sealing'].include?(process_type)
  end

  # Check if this operation is auto-inserted
  def auto_inserted?
    ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test'].include?(process_type)
  end

  # Calculate plating time for ENP operations
  def calculate_plating_time(target_thickness_um)
    return nil unless electroless_nickel_plating? && deposition_rate_range

    OperationLibrary::ElectrolessNickelPlate.calculate_plating_time(id, target_thickness_um)
  end
end
