# app/models/process_library/anodising/chromic_anodising.rb
module ProcessLibrary
  class AnodisingChromic
    def self.processes
      [
        # Chromic Acid Anodise Process 1
        Process.new(
          id: 'CAA_PROC1',
          name: 'Chromic Acid Process 1',
          alloys: ['general'],
          process_type: 'chromic_anodising',
          time_minutes: 40, # Total time: 10+20+5+5
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-40V (over 10 minutes), 40V (hold for 20 minutes), 40-50V (over 5 minutes), 50V (hold for 5 minutes)'
        ),

        # Chromic Acid Anodise Process 2
        Process.new(
          id: 'CAA_PROC2',
          name: 'Chromic Acid Process 2',
          alloys: ['general'],
          process_type: 'chromic_anodising',
          time_minutes: 37, # Total time: 7+30
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-22V (over 7 minutes), 22V (hold over 30 minutes)'
        )
      ]
    end
  end
end
