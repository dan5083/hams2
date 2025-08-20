# app/models/process_library/base.rb
module ProcessLibrary
  # Simple process structure - matching your new field names
  Process = Struct.new(
    :id, :alloys, :process_type, :anodic_classes,
    :target_thickness, :vat_numbers, :operation_text,
    keyword_init: true
  ) do
    def display_name
      id.humanize # Use ID as display name
    end

    def matches_requirements?(alloy:, process_type:, anodic_class: nil, target_thickness: nil)
      # Check if this process matches the requirements
      alloy_match = Array(alloys).any? { |a|
        a.downcase.include?(alloy.downcase) ||
        alloy.downcase.include?(a.downcase) ||
        a == 'general' || a == 'all_alloys'
      }

      type_match = self.process_type == process_type

      # Class match - if no class specified, any process works
      # If class specified, process must support it
      class_match = anodic_class.nil? ||
                   Array(anodic_classes).include?(anodic_class) ||
                   Array(anodic_classes).empty?

      # Thickness match - allow some tolerance
      thickness_match = target_thickness.nil? ||
                       self.target_thickness.nil? ||
                       (self.target_thickness - target_thickness).abs <= 5

      alloy_match && type_match && class_match && thickness_match
    end

    def vat_list
      Array(vat_numbers).join(', ')
    end

    def supports_class?(anodic_class)
      Array(anodic_classes).include?(anodic_class) || Array(anodic_classes).empty?
    end
  end

  # Standard operations that appear in every process
  STANDARD_OPERATIONS = {
    contract_review: {
      position: :first,
      title: "Contract review",
      description: "Route card, PO, and drawing to be checked for errors, issues, and incongruencies (by 'A' Stamp Holder) and contained IAW IP2002."
    },
    pack: {
      position: :last,
      title: "Pack",
      description: "Following IP2011."
    }
  }.freeze

  # Wet process types - categorized by their characteristics for rinse logic
  WET_PROCESS_TYPES = {
    electrochemical: %w[hard_anodising standard_anodising chromic_anodising electroless_nickel electroplating],
    chemical_pretreatment: %w[caustic_etch acid_etch pickling deoxidizing],
    chemical_conversion: %w[chromate_conversion phosphate_conversion passivation],
    cleaning: %w[degreasing alkaline_cleaning solvent_cleaning],
    sealing: %w[hot_sealing cold_sealing dichromate_sealing]
  }.freeze

  # Master registry of all processes
  def self.all_processes
    @all_processes ||= [
      *AnodisingHard.processes,
      *AnodisingSulfuric.processes,
      *AnodisingChromic.processes
      # Add more as we create them
    ].flatten
  end

  # Main suggestion method - this is what PPI creation will use
  def self.suggest_processes(alloy:, process_type:, anodic_class: nil, target_thickness: nil)
    all_processes.select do |process|
      process.matches_requirements?(
        alloy: alloy,
        process_type: process_type,
        anodic_class: anodic_class,
        target_thickness: target_thickness
      )
    end.sort_by { |p| [p.target_thickness || 0, p.id] }
  end

  # Helper to build a complete operation sequence
  def self.build_operation_sequence(main_processes)
    operations = []

    # Always start with contract review
    operations << STANDARD_OPERATIONS[:contract_review]

    # Add the main processes
    main_processes.each do |process|
      operations << {
        title: process.display_name,
        description: process.operation_text,
        process_data: process
      }

      # Note: Rinsing handled by supporting_processes/rinsing.rb
      # Different processes need different rinse types (RO, hot, cold, cascade, etc.)
    end

    # Always end with pack
    operations << STANDARD_OPERATIONS[:pack]

    operations
  end

  # Simple query methods
  def self.find(id)
    all_processes.find { |p| p.id == id }
  end

  def self.process_types
    all_processes.map(&:process_type).uniq.sort
  end

  def self.available_classes
    all_processes.flat_map(&:anodic_classes).compact.uniq.sort
  end

  def self.available_alloys
    all_processes.flat_map(&:alloys).uniq.reject { |a| a == 'general' }.sort
  end

  # Form helper methods
  def self.process_type_options
    process_types.map { |t| [t.humanize, t] }
  end

  def self.class_options
    [
      ['Either/Any', nil],
      ['Class 1 (non-dyed)', 'class_1'],
      ['Class 2 (dyed)', 'class_2']
    ]
  end

  def self.alloy_options
    # Common alloy groupings for dropdown
    [
      ['6000 Series (ex 6063)', '6000_series'],
      ['7075/7050/7021/2099', '7075'],
      ['5083', '5083'],
      ['5054', '5054'],
      ['2014/H15/LT68', '2014'],
      ['2618/H16', '2618'],
      ['2099', '2099'],
      ['LM25 Casting', 'lm25_casting'],
      ['Scalmalloy', 'scalmalloy'],
      ['Titanium', 'titanium'],
      ['6026', '6026'],
      ['General/Other', 'general']
    ]
  end
end
