# app/services/hard_anodise_parser.rb
#
# Pulls the electrical recipe out of a hard anodising operation line.
#
# The operation library writes lines like:
#   "Hard anodise 25V↗️45V over 30 minutes in vat 2"
#   "Hard anodise 25V↗️55V over 30 minutes in vat 2, then hold at 30V for 10 minutes"
#   "Hard anodise 25V↗️50V over 30 minutes in any of vats 1, 3, 9, 12"
#
# Everything after the first line (film thickness note, OCV monitoring grid) is
# ignored — we only parse the recipe line itself so a stray "5min: ___V" in the
# monitoring block can never be mistaken for a set point.
class HardAnodiseParser
  RECIPE_LINE   = /hard\s+anodise/i
  RAMP          = /(\d+(?:\.\d+)?)\s*V\D{0,8}?(\d+(?:\.\d+)?)\s*V\s+over\s+(\d+)\s*min/i
  HOLD          = /hold\s+at\s+(\d+(?:\.\d+)?)\s*V\s+for\s+(\d+)\s*min/i
  SINGLE_VAT    = /\bin\s+vat\s+(\d+)/i
  MULTI_VAT     = /\bin\s+any\s+of\s+vats\s+([\d,\s]+)/i

  Cycle = Struct.new(
    :position, :display_name, :initial_voltage, :final_voltage,
    :duration_minutes, :hold_voltage, :hold_minutes, :vat_numbers,
    :recipe_line, :operation_text,
    keyword_init: true
  ) do
    def hold?  = hold_voltage.present? && hold_minutes.to_i.positive?
    def ramp?  = final_voltage.to_f > initial_voltage.to_f
    def total_minutes = duration_minutes.to_i + hold_minutes.to_i

    # Volts per minute the operator has to wind on at the variac.
    def ramp_rate
      return 0.0 unless duration_minutes.to_i.positive?
      ((final_voltage - initial_voltage) / duration_minutes.to_f).round(2)
    end

    def peak_voltage
      [final_voltage, initial_voltage, hold_voltage].compact.max
    end

    def runs_in_vat?(number)
      vat_numbers.include?(number.to_i)
    end

    # Set points at the same 5-minute cadence the OCV monitoring block uses,
    # so what's on screen lines up with what gets written on the route card.
    def schedule(step = 5)
      marks = (0..duration_minutes.to_i).step(step).to_a
      marks << duration_minutes.to_i unless marks.last == duration_minutes.to_i
      rows = marks.map do |minute|
        { minute: minute, voltage: voltage_at(minute), phase: :ramp }
      end
      if hold?
        rows << { minute: total_minutes, voltage: hold_voltage, phase: :hold }
      end
      rows
    end

    def voltage_at(minute)
      return final_voltage if minute >= duration_minutes.to_i
      return initial_voltage unless duration_minutes.to_i.positive?
      value = initial_voltage + (ramp_rate * minute)
      value.round(1)
    end
  end

  # works_order -> [Cycle]
  def self.cycles_for(works_order)
    operations = works_order.operations_with_auto_ops || []
    operations.each_with_index.filter_map do |operation, index|
      next unless hard_anodising?(operation)
      parse(text_of(operation), position: index + 1, display_name: name_of(operation))
    end
  end

  def self.parse(operation_text, position: nil, display_name: nil)
    return nil if operation_text.blank?

    line = operation_text.to_s.lines.map(&:strip).find { |l| l.match?(RECIPE_LINE) }
    return nil if line.blank?

    ramp = line.match(RAMP)
    return nil if ramp.nil?

    hold = line.match(HOLD)

    Cycle.new(
      position:         position,
      display_name:     display_name,
      initial_voltage:  ramp[1].to_f,
      final_voltage:    ramp[2].to_f,
      duration_minutes: ramp[3].to_i,
      hold_voltage:     hold && hold[1].to_f,
      hold_minutes:     hold ? hold[2].to_i : 0,
      vat_numbers:      vats_in(line),
      recipe_line:      line,
      operation_text:   operation_text
    )
  end

  def self.vats_in(line)
    if (multi = line.match(MULTI_VAT))
      multi[1].scan(/\d+/).map(&:to_i)
    elsif (single = line.match(SINGLE_VAT))
      [single[1].to_i]
    else
      []
    end
  end

  # Library operations expose process_type; operations locked onto a part are
  # plain hashes with "process_type" => "manual", so fall back to the text.
  def self.hard_anodising?(operation)
    type = if operation.respond_to?(:process_type)
             operation.process_type
           elsif operation.is_a?(Hash)
             operation["process_type"] || operation[:process_type]
           end

    return true if type.to_s == "hard_anodising"

    text_of(operation).to_s.match?(RECIPE_LINE)
  end

  def self.text_of(operation)
    if operation.respond_to?(:operation_text)
      operation.operation_text
    elsif operation.is_a?(Hash)
      operation["operation_text"] || operation[:operation_text]
    end
  end

  def self.name_of(operation)
    if operation.respond_to?(:display_name)
      operation.display_name
    elsif operation.is_a?(Hash)
      operation["display_name"] || operation[:display_name]
    end
  end
end
