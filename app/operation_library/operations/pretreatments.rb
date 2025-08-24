# app/operation_library/operations/pretreatments.rb
module OperationLibrary
  class Pretreatments
    def self.operations
      simple_pretreatments + enp_pretreatments
    end

    # Simple pretreatments for anodising processes
    def self.simple_pretreatments
      [
        # Simple DeOx pretreatment for anodising/chemical conversion
        Operation.new(
          id: 'DEOX_OXIDITE_D30',
          process_type: 'pretreatment',
          operation_text: '**DeOx:** in *Oxidite D-30,* at 21 to 43°C, for 30-50 seconds OR in *Microetch 66* at 18-25°C for 1-2 mins'
        )
      ]
    end

    # Complex ENP pretreatments
    def self.enp_pretreatments
      [
        # Ferrous Cleaning Operations
        Operation.new(
          id: 'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          process_type: 'enp_pretreatment',
          operation_text: 'Immerse in Keycote 245 at 35-80°C for 5-20 minutes'
        ),

        # Electroclean Operations
        Operation.new(
          id: 'ELECTROCLEAN_METEX_EMPHAX_4_10_AMP_2_3_MIN',
          process_type: 'enp_pretreatment',
          operation_text: 'Electroclean in Metex Emphax at 4-10 Amp/dm² at 60-95°C for 2-3 minutes'
        ),

        # Activation Operations
        Operation.new(
          id: 'ACTIVATE_M629_30SEC_1MIN_18_52C',
          process_type: 'enp_pretreatment',
          operation_text: 'Activate in M629 for 30 seconds to 1 minute at 18-52°C'
        ),

        Operation.new(
          id: 'ACTIVATE_M629_30SEC_1MIN_18_52C_CELCIUS',
          process_type: 'enp_pretreatment',
          operation_text: 'Activate in M629 for 30 seconds to 1 minute at 18-52°C'
        ),

        # Woods Nickel Strike Operations
        Operation.new(
          id: 'SOAK_WOODS_NICKEL_STRIKE_15_16_MIN_18_43C',
          process_type: 'enp_pretreatment',
          operation_text: 'Soak in Woods Nickel strike for 15-16 minutes at 18-43°C'
        ),

        Operation.new(
          id: 'WOODS_NICKEL_STRIKE_6_10_MIN_2_10V_REDUCE_OUTGASSING',
          process_type: 'enp_pretreatment',
          operation_text: 'Woods nickel strike for 6-10 minutes from 2 to 10 Volts to reduce outgassing'
        ),

        Operation.new(
          id: 'WOODS_NICKEL_STRIKE_6_10_MIN_2_10V_INDUCE_OUTGASSING',
          process_type: 'enp_pretreatment',
          operation_text: 'Woods nickel strike for 6-10 minutes from 2 to 10 Volts to induce outgassing'
        ),

        # Aluminium Cleaning Operations
        Operation.new(
          id: 'ALUMINIUM_CLEAN_KEYCOTE_245_30_60SEC',
          process_type: 'enp_pretreatment',
          operation_text: 'Clean aluminium in Keycote 245 at 35-80°C for 30-60 seconds'
        ),

        # DESMUT Operations
        Operation.new(
          id: 'DESMUT_MICROETCH_66_1_2_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'DESMUT in Microetch 66 at 18-25°C for 1-2 minutes'
        ),

        Operation.new(
          id: 'DESMUT_MICROETCH_66_1_10_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'DESMUT in Microetch 66 at 18-25°C for 1-10 minutes'
        ),

        Operation.new(
          id: 'DESMUT_MICROETCH_66_35_40_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'DESMUT in Microetch 66 at 18-25°C for 35-40 minutes'
        ),

        # Alumon 70 Operations
        Operation.new(
          id: 'ALUMON_70_1_2_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Treat in Alumon 70 at 18-25°C for 1-2 minutes'
        ),

        # Zincate Operations
        Operation.new(
          id: 'ZINCATE_BONDAL_HALF_2_MIN_18_30C',
          process_type: 'enp_pretreatment',
          operation_text: 'Zincate in Bondal at 18-30°C for 1/2 to 2 minutes'
        ),

        # Etch Operations
        Operation.new(
          id: 'ETCH_AWAY_ZINCATE_MICROETCH_66_20_40SEC_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Etch away zincate with Microetch 66 at 18-25°C for 20-40 seconds'
        ),

        # Pickling Operations
        Operation.new(
          id: 'PICKLING_ALUMON_70_2_3_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Pickle using Alumon 70 for 2-3 minutes at 18-25°C'
        ),

        Operation.new(
          id: 'PICKLING_ALUMON_70_9_11_MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Pickle using Alumon 70 for 9-11 minutes at 18-25°C'
        ),

        # Acid Operations
        Operation.new(
          id: 'ACID_DIP_M629_10SEC_1MIN_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Acid dip in M629 for 10 seconds to 1 minute at 18-25°C'
        ),

        Operation.new(
          id: 'ACID_ETCH_MICROETCH_66_20_40SEC_18_25C',
          process_type: 'enp_pretreatment',
          operation_text: 'Acid etch with Microetch 66 at 18-25°C for 20-40 seconds'
        ),

        # Microetch Operations
        Operation.new(
          id: 'MICROETCH_66_20_30SEC',
          process_type: 'enp_pretreatment',
          operation_text: 'Microetch 66 for 20-30 seconds'
        ),

        Operation.new(
          id: 'MICROETCH_66_30_40SEC',
          process_type: 'enp_pretreatment',
          operation_text: 'Microetch 66 for 30-40 seconds'
        )
      ]
    end

    # Check if pretreatment is required
    def self.pretreatment_required?(user_operations)
      surface_treatment_processes = %w[
        standard_anodising
        hard_anodising
        chromic_anodising
        chemical_conversion
        electroless_nickel_plating
      ]

      user_operations.any? { |op| surface_treatment_processes.include?(op.process_type) }
    end

    # Get the appropriate pretreatment sequence
    def self.get_pretreatment_sequence(user_operations, selected_alloy = nil)
      return [] unless pretreatment_required?(user_operations)

      # Check if ENP is present AND we have an alloy selected
      has_enp = user_operations.any? { |op| op.process_type == 'electroless_nickel_plating' }

      if has_enp && selected_alloy.present?
        # Complex ENP pretreatment sequence with RO rinses
        get_enp_pretreatment_sequence(selected_alloy)
      elsif !has_enp
        # Simple pretreatment for anodising/chemical conversion only
        [get_simple_pretreatment_operation]
      else
        # ENP is present but no alloy selected - return empty array
        # This enforces that ENP requires alloy selection for pretreatments
        []
      end
    end

    # Get simple pretreatment operation
    def self.get_simple_pretreatment_operation
      simple_pretreatments.first
    end

    # Get ENP pretreatment sequence for specific alloy
    def self.get_enp_pretreatment_sequence(alloy)
      sequence_ids = enp_sequences[alloy.upcase.to_sym] || []
      return [] if sequence_ids.empty?

      # Get the operations for this sequence (no manual RO rinses - let auto system handle them)
      pretreatment_ops = enp_pretreatments
      sequence_ids.map do |operation_id|
        pretreatment_ops.find { |op| op.id == operation_id }
      end.compact
    end

    # ENP pretreatment sequences by alloy
    def self.enp_sequences
      {
        STEEL: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'ELECTROCLEAN_METEX_EMPHAX_4_10_AMP_2_3_MIN',
          'ACTIVATE_M629_30SEC_1MIN_18_52C'
        ],

        STAINLESS_STEEL: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'SOAK_WOODS_NICKEL_STRIKE_15_16_MIN_18_43C',
          'WOODS_NICKEL_STRIKE_6_10_MIN_2_10V_REDUCE_OUTGASSING'
        ],

        ALUMINIUM: [
          'ALUMINIUM_CLEAN_KEYCOTE_245_30_60SEC',
          'DESMUT_MICROETCH_66_1_2_MIN_18_25C',
          'ALUMON_70_1_2_MIN_18_25C',
          'DESMUT_MICROETCH_66_1_2_MIN_18_25C',
          'ZINCATE_BONDAL_HALF_2_MIN_18_30C',
          'ETCH_AWAY_ZINCATE_MICROETCH_66_20_40SEC_18_25C',
          'ZINCATE_BONDAL_HALF_2_MIN_18_30C'
        ],

        STAINLESS_STEEL_WITH_OXIDES: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'PICKLING_ALUMON_70_2_3_MIN_18_25C',
          'SOAK_WOODS_NICKEL_STRIKE_15_16_MIN_18_43C',
          'WOODS_NICKEL_STRIKE_6_10_MIN_2_10V_INDUCE_OUTGASSING'
        ],

        COPPER_SANS_ELECTRICAL_CONTACT: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'ACID_DIP_M629_10SEC_1MIN_18_25C',
          'ACID_ETCH_MICROETCH_66_20_40SEC_18_25C'
        ],

        MCLAREN_STA142_PROCEDURE_D: [
          'ALUMON_70_1_2_MIN_18_25C',
          'DESMUT_MICROETCH_66_1_10_MIN_18_25C'
        ],

        BRASS: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'ELECTROCLEAN_METEX_EMPHAX_4_10_AMP_2_3_MIN',
          'ACTIVATE_M629_30SEC_1MIN_18_52C_CELCIUS',
          'MICROETCH_66_20_30SEC'
        ],

        COPPER: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'ELECTROCLEAN_METEX_EMPHAX_4_10_AMP_2_3_MIN',
          'MICROETCH_66_30_40SEC',
          'ACTIVATE_M629_30SEC_1MIN_18_52C_CELCIUS'
        ],

        TWO_THOUSAND_SERIES_ALLOYS: [
          'ALUMINIUM_CLEAN_KEYCOTE_245_30_60SEC',
          'DESMUT_MICROETCH_66_1_2_MIN_18_25C',
          'ALUMON_70_1_2_MIN_18_25C',
          'DESMUT_MICROETCH_66_35_40_MIN_18_25C',
          'ZINCATE_BONDAL_HALF_2_MIN_18_30C',
          'ETCH_AWAY_ZINCATE_MICROETCH_66_20_40SEC_18_25C',
          'ZINCATE_BONDAL_HALF_2_MIN_18_30C'
        ],

        CAST_ALUMINIUM_WILLIAM_COPE: [
          'ALUMINIUM_CLEAN_KEYCOTE_245_30_60SEC',
          'ALUMON_70_1_2_MIN_18_25C',
          'DESMUT_MICROETCH_66_1_2_MIN_18_25C'
        ],

        THREE_ONE_SIX_STAINLESS_STEEL: [
          'FERROUS_CLEANING_KEYCOTE_245_5_20_MIN',
          'PICKLING_ALUMON_70_9_11_MIN_18_25C',
          'SOAK_WOODS_NICKEL_STRIKE_15_16_MIN_18_43C',
          'WOODS_NICKEL_STRIKE_6_10_MIN_2_10V_INDUCE_OUTGASSING'
        ]
      }
    end

    # Get available alloys for ENP pretreatment
    def self.available_enp_alloys
      enp_sequences.keys.map(&:to_s).map(&:downcase)
    end

    # Insert pretreatments into operation sequence
    def self.insert_pretreatments_if_required(operations_sequence, selected_alloy = nil)
      return operations_sequence unless pretreatment_required?(operations_sequence)

      pretreatment_ops = get_pretreatment_sequence(operations_sequence, selected_alloy)
      return operations_sequence if pretreatment_ops.empty?

      # Insert after VAT inspection but before jigging/degrease
      insertion_index = operations_sequence.find_index { |op|
        op.process_type == 'vat_inspect'
      }

      if insertion_index
        # Insert after VAT inspection
        operations_sequence.insert(insertion_index + 1, *pretreatment_ops)
      else
        # Fallback: insert at beginning
        pretreatment_ops + operations_sequence
      end
    end
  end
end
