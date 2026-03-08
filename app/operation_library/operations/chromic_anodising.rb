# app/operation_library/anodising/chromic_anodising.rb
module OperationLibrary
  class AnodisingChromic
    def self.operations(aerospace_defense = nil)
      # Default to aerospace/defense true if not specified to maintain existing behavior
      aerospace_defense = true if aerospace_defense.nil?

      base_operations.map do |operation_data|
        create_operation(operation_data, aerospace_defense)
      end
    end

    private

    def self.create_operation(data, aerospace_defense)
      # The ending text is now dynamically generated based on aerospace/defense flag
      base_text = data[:operation_text]

      ending_text = if aerospace_defense
        " -- check film thickness against specification, if out of range inform an A stampholder"
      else
        " -- check film thickness against specification, if out of range inform an A stampholder\n-- record film thickness ___ μm"
      end

      operation_text = base_text + ending_text

      # Append OCV monitoring for aerospace/defense (chromic has special checkpoints)
      if aerospace_defense
        ocv_text = build_chromic_voltage_monitoring_text(data[:id])
        operation_text += "\n\n**OCV Monitoring:**\n#{ocv_text}"
      end

      Operation.new(
        id: data[:id],
        alloys: data[:alloys],
        process_type: 'chromic_anodising',
        anodic_classes: data[:anodic_classes] || [],
        target_thickness: data[:target_thickness] || 0,
        vat_numbers: data[:vat_numbers],
        operation_text: operation_text
      )
    end

    def self.build_chromic_voltage_monitoring_text(operation_id)
      checkpoints = case operation_id
      when 'CAA_40_50V_40MIN'
        # Check at key transition points: 10min (40V reached), 30min (before ramp), 35min (50V reached), 40min (end)
        [
          { time: 10, label: '10min (40V)' },
          { time: 30, label: '30min (40V held)' },
          { time: 35, label: '35min (50V)' },
          { time: 40, label: '40min (end)' }
        ]
      when 'CAA_22V_37MIN'
        # Check at: 7min (22V reached), 20min (mid-hold), 37min (end)
        [
          { time: 7, label: '7min (22V)' },
          { time: 20, label: '20min (held)' },
          { time: 37, label: '37min (end)' }
        ]
      else
        # Fallback for unknown chromic processes
        [
          { time: 10, label: '10min' },
          { time: 20, label: '20min' },
          { time: 30, label: '30min' }
        ]
      end

      # Build monitoring text for 3 batches with chromic-specific checkpoints
      text_lines = []
      (1..3).each do |batch|
        checkpoint_texts = checkpoints.map do |cp|
          "#{cp[:label]}: ___V"
        end
        text_lines << "Batch ___: Temp ___°C [#{checkpoint_texts.join(' | ')}]"
      end

      text_lines.join("\n")
    end

    def self.base_operations
      [
        # Chromic Acid Anodise Process 1 - High voltage variant (NOT available for 7075)
        {
          id: 'CAA_40_50V_40MIN',
          alloys: ['general', 'aluminium', '6000_series', '2024'],
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-40V (over 10 minutes), 40V (hold for 20 minutes), 40-50V (over 5 minutes), 50V (hold for 5 minutes)'
        },

        # Chromic Acid Anodise Process 2 - Standard voltage variant (available to all alloys, but ONLY option for 7075)
        {
          id: 'CAA_22V_37MIN',
          alloys: ['general', 'aluminium', '6000_series', '7075', '2024'],
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-22V (over 7 minutes), 22V (hold over 30 minutes)'
        }
      ]
    end
  end
end
