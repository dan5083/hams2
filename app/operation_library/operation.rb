# app/operation_library/operation.rb - Updated to handle dye operations
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

    # Add dye operations
    operations += OperationLibrary::Dye.operations if defined?(OperationLibrary::Dye)

    # Add PTFE operations
    operations += OperationLibrary::Ptfe.operations if defined?(OperationLibrary::Ptfe)

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
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe']
    matching = all_operations(target_thickness).reject { |op| auto_inserted_types.include?(op.process_type) }

    matching = matching.select { |op| op.process_type == process_type } if process_type.present?
    matching = matching.select { |op| op.alloys.include?(alloy) } if alloy.present?

    # Skip anodic class filtering for chromic anodising
    if anodic_class.present?
      matching = matching.select { |op|
        if op.process_type == 'chromic_anodising'
          true
        else
          op.anodic_classes.include?(anodic_class)
        end
      }
    end

    matching = matching.select { |op| op.enp_type == enp_type } if enp_type.present?

    # For thickness, find operations that match exactly or are close (skip for ENP, chemical conversion, chromic anodising, masking, stripping, sealing, dichromate_sealing, water_break_test, and dye)
    if target_thickness.present?
      target = target_thickness.to_f
      matching = matching.select do |op|
        # Skip thickness filtering for chemical conversion, ENP, chromic anodising, masking, stripping, sealing, dichromate_sealing, water_break_test, dye, ptfe, and ENP Strip Mask
        if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'chromic_anodising', 'masking', 'stripping', 'sealing', 'dichromate_sealing', 'water_break_test', 'dye', 'ptfe']) ||
           ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type)
          true
        else
          # Exact match or within reasonable tolerance (±2.5μm)
          (op.target_thickness - target).abs <= 2.5
        end
      end
      # Sort by closest thickness match (but only for standard/hard anodising operations)
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        matching = matching.sort_by do |op|
          if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'chromic_anodising', 'masking', 'stripping', 'sealing', 'dichromate_sealing', 'water_break_test', 'dye']) ||
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
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.map(&:process_type).uniq.sort
  end

  def self.available_alloys
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe']
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) }.flat_map(&:alloys).uniq.sort
  end

  def self.available_anodic_classes
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe']
    # Exclude chromic anodising from anodic class availability since it doesn't use classes
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) || op.process_type == 'chromic_anodising' }.flat_map(&:anodic_classes).uniq.sort
  end

  def self.available_thicknesses
    auto_inserted_types = ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe']
    # Exclude chromic anodising, dye, and PTFE from thickness availability since they use fixed thickness or no thickness
    all_operations.reject { |op| auto_inserted_types.include?(op.process_type) || op.process_type == 'chromic_anodising' || op.process_type == 'dye' || op.process_type == 'ptfe' }.map(&:target_thickness).uniq.select { |t| t > 0 }.sort
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

  def self.dye_operations
    all_operations.select { |op| op.process_type == 'dye' }
  end

  def self.ptfe_operations
    all_operations.select { |op| op.process_type == 'ptfe' }
  end

  # Instance methods
  def display_name
    case process_type
    when 'contract_review'
      'Contract Review'
    when 'inspect'
      'Inspect'
    when 'vat_inspect'
      'VAT Inspect'
    when 'final_inspect'
      'Final Inspect'
    when 'water_break_test'
      'Water Break'
    when 'pretreatment'
      'DeOx'
    when 'enp_pretreatment'
      case id
      when /FERROUS_CLEANING/
        'Clean'
      when /ELECTROCLEAN/
        'Electroclean'
      when /ACTIVATE/
        'Activate'
      when /WOODS_NICKEL/
        'Woods Nickel'
      when /ALUMINIUM_CLEAN/
        'Alu Clean'
      when /DESMUT/
        'Desmut'
      when /ALUMON/
        'Alumon'
      when /ETCH_AWAY/
        'Strip Zincate'
      when /ZINCATE/
        'Zincate'
      when /PICKLING/
        'Pickle'
      when /ACID_DIP/
        'Acid Dip'
      when /ACID_ETCH/
        'Acid Etch'
      when /MICROETCH/
        'Microetch'
      else
        'ENP Pretreat'
      end
    when 'jig'
      'Jig'
    when 'unjig'
      'Unjig'
    when 'degrease'
      'Degrease'
    when 'pack'
      'Pack'
    when 'masking_removal'
      'Remove Mask'
    when 'masking_removal_check'
      'Check Mask Removal'
    when 'masking_inspection'
      'Inspect Mask'
    when 'mask'
      'ENP Mask'
    when 'masking_check'
      'Check Mask'
    when 'strip'
      case id
      when 'ENP_STRIP_NITRIC'
        'Strip (Nitric)'
      when 'ENP_STRIP_METEX'
        'Strip (Metex)'
      else
        'Strip'
      end
    when 'strip_masking'
      'Strip Mask'
    when 'sealing', 'dichromate_sealing'
      case id
      when 'SODIUM_DICHROMATE_SEAL'
        'Dichromate Seal'
      when 'OXIDITE_SECO_SEAL'
        'SE-CO Seal'
      when 'HOT_WATER_DIP'
        'Hot Dip'
      when 'HOT_SEAL'
        'Hot Seal'
      when 'SURTEC_650V_SEAL'
        '650V Seal'
      when 'DEIONISED_WATER_SEAL'
        'DI Water Seal'
      else
        'Seal'
      end
    when 'dye'
      id.sub('_DYE', '').capitalize
    when 'ptfe'
      'PTFE'
    when 'rinse'
      case id
      when 'CASCADE_RINSE'
        'Cascade Rinse'
      when 'CASCADE_RINSE_BUNGS'
        'Cascade Rinse (Bungs)'
      when 'CASCADE_RINSE_5MIN_WAIT'
        'Cascade (5min)'
      when 'CASCADE_RINSE_5MIN_WAIT_BUNGS'
        'Cascade (5min, Bungs)'
      when 'RO_RINSE', 'RO_RINSE_PRETREATMENT'
        'RO Rinse'
      else
        'Rinse'
      end
    when 'electroless_nickel_plating'
      case enp_type
      when 'high_phosphorous'
        'High P ENP'
      when 'medium_phosphorous'
        'Med P ENP'
      when 'low_phosphorous'
        'Low P ENP'
      when 'ptfe_composite'
        'PTFE ENP'
      else
        'ENP'
      end
    when 'chromic_anodising'
      case id
      when 'CAA_40_50V_40MIN'
        'CAA (50V)'
      when 'CAA_22V_37MIN'
        'CAA (22V)'
      else
        'CAA'
      end
    when 'standard_anodising'
      "Std Ano (#{target_thickness}μm)"
    when 'hard_anodising'
      "Hard Ano (#{target_thickness}μm)"
    when 'chemical_conversion'
      id.split('_').first.capitalize
    else
      target_thickness > 0 ? "#{id} (#{target_thickness}μm)" : id.humanize
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

    # Skip anodic class check for chromic anodising
    if anodic_class.present? && self.process_type != 'chromic_anodising'
      return false unless anodic_classes.include?(anodic_class)
    end

    return false if enp_type.present? && self.enp_type != enp_type

    # Skip thickness check for chromic anodising, dye, and PTFE
    if target_thickness.present? && self.process_type != 'electroless_nickel_plating' &&
       self.process_type != 'chemical_conversion' && self.process_type != 'chromic_anodising' &&
       self.process_type != 'dye' && self.process_type != 'ptfe' &&
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

  def chromic_anodising?
    process_type == 'chromic_anodising'
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

  def dye?
    process_type == 'dye'
  end

  def ptfe?
    process_type == 'ptfe'
  end

  # Check if this operation is auto-inserted
  def auto_inserted?
    ['rinse', 'degrease', 'contract_review', 'pack', 'inspect', 'vat_inspect', 'final_inspect', 'jig', 'unjig', 'masking_removal', 'masking_removal_check', 'masking_inspection', 'pretreatment', 'enp_pretreatment', 'water_break_test', 'dye', 'ptfe'].include?(process_type)
  end

  # Calculate plating time for ENP operations
  def calculate_plating_time(target_thickness_um)
    return nil unless electroless_nickel_plating? && deposition_rate_range

    OperationLibrary::ElectrolessNickelPlate.calculate_plating_time(id, target_thickness_um)
  end
end
