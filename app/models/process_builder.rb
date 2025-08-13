class ProcessBuilder
  # Basic process types for anodising shop
  AVAILABLE_TYPES = %w[
    anodising
    hard_anodising
    chromate_conversion
    passivation
    cleaning
    custom
  ].freeze

  def self.available_types
    AVAILABLE_TYPES
  end

  def self.for_type(process_type)
    new(process_type)
  end

  def self.build_process(process_type, customisation_data, part: nil)
    # Simple implementation - just return the customisation data
    # In the future this could build complex process steps
    {
      process_type: process_type,
      customisations: customisation_data,
      part_info: part&.display_name
    }
  end

  def initialize(process_type)
    @process_type = process_type
  end

  def available_customizations
    # Simple customization options for now
    case @process_type
    when 'anodising', 'hard_anodising'
      {
        thickness: ['10 microns', '15 microns', '20 microns', '25 microns', '30 microns'],
        finish: ['Natural', 'Black', 'Red', 'Blue', 'Gold'],
        sealing: ['Sealed', 'Unsealed']
      }
    when 'chromate_conversion'
      {
        type: ['Iridite 14-2', 'Iridite NCP', 'Alodine 1200'],
        finish: ['Clear', 'Gold']
      }
    when 'passivation'
      {
        type: ['Citric Acid', 'Nitric Acid'],
        duration: ['30 minutes', '60 minutes', '90 minutes']
      }
    else
      {
        notes: 'Free text for custom processes'
      }
    end
  end
end
