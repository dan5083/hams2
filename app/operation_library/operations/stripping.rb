# app/operation_library/operations/stripping.rb
module OperationLibrary
  class Stripping
    # Available stripping types and methods
    STRIPPING_TYPES = [
      { value: 'anodising_stripping', label: 'Anodising Stripping' },
      { value: 'enp_stripping', label: 'ENP Stripping' },
      { value: 'general_stripping', label: 'General Stripping' }
    ].freeze

    ANODISING_STRIPPING_METHODS = [
      { value: 'chromic_phosphoric', label: 'Chromic-Phosphoric Acid' },
      { value: 'sulphuric_sodium_hydroxide', label: 'Sulphuric Acid + Sodium Hydroxide' },
      { value: 'sodium_hydroxide', label: 'Sodium Hydroxide' }
    ].freeze

    ENP_STRIPPING_METHODS = [
      { value: 'nitric', label: 'Nitric Acid' },
      { value: 'metex_dekote', label: 'Metex Dekote' }
    ].freeze

    GENERAL_STRIPPING_METHODS = [
      { value: 'sodium_hydroxide', label: 'Sodium Hydroxide' },
      { value: 'chromic_phosphoric', label: 'Chromic-Phosphoric Acid' },
      { value: 'sulphuric_sodium_hydroxide', label: 'Sulphuric Acid + Sodium Hydroxide' },
      { value: 'nitric', label: 'Nitric Acid' },
      { value: 'metex_dekote', label: 'Metex Dekote' }
    ].freeze

    def self.operations(stripping_type = nil, stripping_method = nil)
      [
        Operation.new(
          id: 'STRIPPING',
          process_type: 'stripping',
          operation_text: build_stripping_text(stripping_type, stripping_method)
        )
      ]
    end

    # Get available stripping types for form selection
    def self.available_types
      STRIPPING_TYPES
    end

    # Get available methods for a given stripping type
    def self.available_methods_for_type(stripping_type)
      case stripping_type
      when 'anodising_stripping'
        ANODISING_STRIPPING_METHODS
      when 'enp_stripping'
        ENP_STRIPPING_METHODS
      when 'general_stripping'
        GENERAL_STRIPPING_METHODS
      else
        []
      end
    end

    # Build the operation text based on stripping type and method
    def self.build_stripping_text(stripping_type = nil, stripping_method = nil)
      return 'Strip as specified' if stripping_type.blank? || stripping_method.blank?

      case stripping_type
      when 'anodising_stripping'
        build_anodising_stripping_text(stripping_method)
      when 'enp_stripping'
        build_enp_stripping_text(stripping_method)
      when 'general_stripping'
        build_general_stripping_text(stripping_method)
      else
        'Strip as specified'
      end
    end

    # Get the stripping operation with interpolated text
    def self.get_stripping_operation(stripping_type = nil, stripping_method = nil)
      Rails.logger.info "🔍 Stripping called with type=#{stripping_type}, method=#{stripping_method}"
      result = operations(stripping_type, stripping_method).first
      Rails.logger.info "🔍 Stripping result: #{result.inspect}"
      result
    end

    # Check if stripping is configured
    def self.stripping_configured?(stripping_type, stripping_method)
      stripping_type.present? && stripping_method.present?
    end

    private

    def self.build_anodising_stripping_text(method)
      case method
      when 'chromic_phosphoric'
        'Strip anodising in chromic-phosphoric acid solution'
      when 'sulphuric_sodium_hydroxide'
        'Soak in sulphuric acid solution then strip in sodium hydroxide solution'
      when 'sodium_hydroxide'
        'Strip in sodium hydroxide solution - wait till fizzing starts and hold for 30 seconds'
      else
        'Strip anodising as specified'
      end
    end

    def self.build_enp_stripping_text(method)
      case method
      when 'nitric'
        'Strip ENP in nitric acid solution 30 to 40 minutes per 25 microns [or until black smut dissolves]'
      when 'metex_dekote'
        'Strip ENP in Metex Dekote at 80 to 90°C, for approximately 20 microns per hour strip rate'
      else
        'Strip ENP as specified'
      end
    end

    def self.build_general_stripping_text(method)
      case method
      when 'sodium_hydroxide'
        'Strip in sodium hydroxide solution - wait till fizzing starts and hold for 30 seconds'
      when 'chromic_phosphoric'
        'Strip in chromic-phosphoric acid solution'
      when 'sulphuric_sodium_hydroxide'
        'Soak in sulphuric acid solution then strip in sodium hydroxide solution'
      when 'nitric'
        'Strip in nitric acid solution'
      when 'metex_dekote'
        'Strip in Metex Dekote at 80 to 90°C'
      else
        'Strip as specified'
      end
    end
  end
end
