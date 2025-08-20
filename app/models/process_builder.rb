# app/models/process_builder.rb
class ProcessBuilder
  # Updated to work with new ProcessLibrary structure
  def self.available_types
    ProcessLibrary.process_types
  end

  def self.for_type(process_type)
    new(process_type)
  end

  # Main method to suggest processes based on requirements
  def self.suggest_processes(alloy:, process_type:, anodic_class: nil, target_thickness: nil)
    ProcessLibrary.suggest_processes(
      alloy: alloy,
      process_type: process_type,
      anodic_class: anodic_class,
      target_thickness: target_thickness
    )
  end

  # Build a process from ProcessLibrary template with customizations
  def self.build_process(process_id, customisation_data = {}, part: nil)
    template = ProcessLibrary.find(process_id)
    return {} unless template

    {
      template: template,
      operation_text: template.operation_text,
      customisations: customisation_data,
      part_info: part&.display_name,
      process_type: template.process_type,
      vat_numbers: template.vat_numbers,
      target_thickness: template.target_thickness
    }
  end

  # Build complete operation sequence for route cards
  def self.build_operation_sequence(process_ids, customisation_data = {})
    processes = process_ids.map { |id| ProcessLibrary.find(id) }.compact
    ProcessLibrary.build_operation_sequence(processes)
  end

  # Get all available alloy options
  def self.alloy_options
    ProcessLibrary.alloy_options
  end

  # Get all available class options
  def self.class_options
    ProcessLibrary.class_options
  end

  def initialize(process_type)
    @process_type = process_type
  end

  # Get processes for this specific type
  def available_processes
    ProcessLibrary.all_processes.select { |p| p.process_type == @process_type }
  end

  # Legacy method for backward compatibility - simplified
  def available_customizations
    case @process_type
    when 'hard_anodising', 'standard_anodising'
      {
        thickness: ['5μm', '10μm', '15μm', '20μm', '25μm', '30μm', '35μm', '40μm', '45μm', '50μm'],
        finish: ['Natural', 'Black', 'Red', 'Blue', 'Gold'],
        class: ['Class 1 (non-dyed)', 'Class 2 (dyed)']
      }
    when 'chromic_anodising'
      {
        thickness: ['1μm', '2μm', '2.5μm', '3μm'],
        finish: ['Natural', 'Clear']
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

  # Convert ProcessLibrary process to route card operation format
  def self.process_to_operation(process, operation_number = 1)
    {
      number: operation_number,
      title: process.display_name,
      content: [
        {
          type: 'paragraph',
          as_html: process.operation_text
        }
      ],
      all_variables: [], # No variables for now - can be enhanced later
      process_data: process
    }
  end

  # Helper to build route card operations from multiple processes
  def self.build_route_card_operations(process_ids)
    operations = []
    operation_number = 1

    # Always start with contract review
    operations << {
      number: operation_number,
      title: "Contract review",
      content: [
        {
          type: 'paragraph',
          as_html: "Route card, PO, and drawing to be checked for errors, issues, and incongruencies (by 'A' Stamp Holder) and contained IAW IP2002."
        }
      ],
      all_variables: []
    }
    operation_number += 1

    # Add selected processes
    process_ids.each do |process_id|
      process = ProcessLibrary.find(process_id)
      next unless process

      operations << process_to_operation(process, operation_number)
      operation_number += 1
    end

    # Always end with pack
    operations << {
      number: operation_number,
      title: "Pack",
      content: [
        {
          type: 'paragraph',
          as_html: "Following IP2011."
        }
      ],
      all_variables: []
    }

    operations
  end
end
