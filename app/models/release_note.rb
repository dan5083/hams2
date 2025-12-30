# app/models/release_note.rb
# app/models/release_note.rb - Updated to support multiple Elcometer readings per treatment
require 'digest/sha2'

class ReleaseNote < ApplicationRecord
  include CustomerOrderCounterCache

  belongs_to :works_order
  belongs_to :issued_by, class_name: 'User'
  has_one :invoice_item, dependent: :nullify
  has_many :external_ncrs, dependent: :restrict_with_error

  validates :date, presence: true
  validates :quantity_accepted, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_rejected, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :total_quantity_must_be_positive
  validate :quantity_available_for_release, unless: :invoiced?
  validate :validate_thickness_measurements

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }

  scope :requires_invoicing, -> {
    left_joins(:invoice_item)
      .where(invoice_items: { id: nil })
      .where(voided: false)
      .where('quantity_accepted > 0')
      .where.not(no_invoice: true)
  }

  scope :invoiced, -> { joins(:invoice_item) }
  scope :ready_for_invoice, -> { requires_invoicing }
  scope :recent, -> { order(number: :desc) }

  before_validation :set_date, if: :new_record?
  before_validation :assign_next_number, if: :new_record?
  after_initialize :set_defaults, if: :new_record?
  after_save :update_works_order_quantity_released, unless: :invoiced?
  after_destroy :update_works_order_quantity_released

  after_save :update_customer_order_uninvoiced_count, if: :saved_change_to_invoicing_status?
  after_destroy :update_customer_order_uninvoiced_count

  # Process types that can have thickness measurements
  MEASURABLE_PROCESS_TYPES = %w[
    chromic_anodising
    hard_anodising
    standard_anodising
    electroless_nickel_plating
    enp_high_phosphorous
    enp_medium_phosphorous
  ].freeze

  def display_name
    "RN#{number}"
  end

  # Delegate customer info to works_order
  def customer
    works_order.customer
  end

  def invoice_customer_name
    works_order.invoice_customer_name
  end

  def invoice_address
    works_order.invoice_address
  end

  def delivery_customer_name
    works_order.delivery_customer_name
  end

  def delivery_address
    works_order.delivery_address
  end

  def specification
    works_order.specification
  end

  def release_statement
    remarks || ''
  end

  def total_quantity
    quantity_accepted + quantity_rejected
  end

  def quantity_summary
    if quantity_rejected > 0
      "#{quantity_accepted} accepted, #{quantity_rejected} rejected"
    else
      quantity_accepted.to_s
    end
  end

  def void!
    transaction do
      if invoice_item.present?
        raise StandardError, "Cannot void release note that has been invoiced"
      end
      update!(voided: true)
    end
  end

  def can_be_voided?
    invoice_item.blank?
  end

  def can_be_invoiced?
    !voided && quantity_accepted > 0 && !no_invoice
  end

  def can_be_edited?
    !voided
  end

  def can_edit_quantities?
    invoiced?
  end

  def can_edit_remarks?
    true
  end

  def invoiced?
    invoice_item.present?
  end

  def ready_for_invoice?
    can_be_invoiced? && invoice_item.blank?
  end

  def invoice_status
    return :voided if voided
    return :invoiced if invoiced?
    return :ready if ready_for_invoice?
    return :no_invoice if no_invoice
    :unknown
  end

  def invoice_description
    "#{works_order.part_number}-#{works_order.part_issue} x #{quantity_accepted}"
  end

  def invoice_value
    case works_order.price_type
    when 'each'
      quantity_accepted * (works_order.each_price || 0)
    when 'lot'
      return 0 if works_order.quantity.zero?
      (quantity_accepted.to_f / works_order.quantity) * works_order.lot_price
    else
      0
    end
  end

  def editing_invoiced_warning
    return nil unless invoiced?
    "⚠️ This release note has been invoiced. Editing quantities will not affect the invoice amounts."
  end

  def show_invoice_impact_warning?
    invoiced? && (quantity_accepted_changed? || quantity_rejected_changed?)
  end

  # THICKNESS MEASUREMENT METHODS - Updated to support multiple readings

  def requires_thickness_measurements?
    return false unless works_order.part&.aerospace_defense?
    get_required_treatments.any?
  end

  def get_required_treatments
    return [] unless works_order.part

    begin
      treatments_data = works_order.part.send(:parse_treatments_data)

      measurable_treatments = treatments_data.select do |treatment|
        MEASURABLE_PROCESS_TYPES.include?(treatment["type"])
      end

      measurable_treatments.map.with_index do |treatment, index|
        {
          treatment_id: generate_treatment_id(treatment, index),
          process_type: treatment["type"],
          target_thickness: treatment["target_thickness"] || 0,
          display_name: generate_display_name(treatment)
        }
      end
    rescue => e
      Rails.logger.error "Error getting required treatments for thickness measurement: #{e.message}"
      []
    end
  end

  # Get thickness readings for a treatment (returns array)
  # Handles both new format (readings array) and old format (single measured_thickness)
  def get_thickness_readings(treatment_id)
    return [] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [] unless measurement

    # New format: readings array
    if measurement['readings'].is_a?(Array)
      measurement['readings']
    # Old format: single measured_thickness value - convert to array
    elsif measurement['measured_thickness'].present?
      [measurement['measured_thickness']]
    else
      []
    end
  end

  # Get mean thickness for a treatment (for backward compatibility and display)
  def get_thickness_measurement(treatment_id)
    readings = get_thickness_readings(treatment_id)
    return nil if readings.empty?
    calculate_mean(readings)
  end

  # Get statistics for a treatment's readings
  def get_thickness_statistics(treatment_id)
    readings = get_thickness_readings(treatment_id)
    return nil if readings.empty?

    {
      count: readings.count,
      mean: calculate_mean(readings),
      min: readings.min,
      max: readings.max
    }
  end

  # Set thickness measurement - accepts either single value OR array of readings
  def set_thickness_measurement(treatment_id, value_or_readings, treatment_info = {})
    # Initialize the structure if needed
    self.measured_thicknesses = { 'measurements' => [] } unless measured_thicknesses.is_a?(Hash)
    self.measured_thicknesses['measurements'] ||= []

    # Find existing measurement or create new one
    measurement = self.measured_thicknesses['measurements'].find { |m| m['treatment_id'] == treatment_id }

    if measurement
      # Update existing measurement
      if value_or_readings.blank? || (value_or_readings.is_a?(Array) && value_or_readings.empty?)
        # Remove measurement if value/readings are blank
        self.measured_thicknesses['measurements'].reject! { |m| m['treatment_id'] == treatment_id }
      else
        measurement['readings'] = process_thickness_readings(value_or_readings)
      end
    elsif value_or_readings.present?
      # Add new measurement
      readings = process_thickness_readings(value_or_readings)
      return false if readings.empty?

      new_measurement = {
        'treatment_id' => treatment_id,
        'process_type' => treatment_info[:process_type],
        'target_thickness' => treatment_info[:target_thickness] || 0,
        'display_name' => treatment_info[:display_name],
        'readings' => readings
      }
      self.measured_thicknesses['measurements'] << new_measurement
    end

    true
  rescue ArgumentError
    false
  end

  def has_thickness_measurements?
    return false unless measured_thicknesses.is_a?(Hash)
    measurements = measured_thicknesses['measurements']
    return false unless measurements.present?

    # Check for either anodic readings OR ENP measurements
    measurements.any? do |m|
      (m['readings'].present? && m['readings'].any?) ||
      (m['enp_measurements'].present? && m['enp_measurements'].any?)
    end
  end

  def thickness_measurements_summary
    return nil unless has_thickness_measurements?

    measurements = measured_thicknesses['measurements'] || []
    summary_parts = measurements.filter_map do |measurement|
      display_name = measurement['display_name'] || measurement['process_type'].humanize.titleize

      # Check if this is ENP or anodic
      if measurement['enp_measurements'].present? && measurement['enp_measurements'].any?
        # ENP measurement
        enp_data = measurement['enp_measurements']
        valid_growths = enp_data.map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }
        next if valid_growths.empty?

        mean = calculate_mean(valid_growths)
        count = valid_growths.count
        "#{display_name}: #{mean} µm growth (#{count}/6 points)"

      elsif measurement['readings'].present? && measurement['readings'].any?
        # Anodic measurement
        readings = measurement['readings']
        mean = calculate_mean(readings)
        count = readings.count

        if count == 1
          "#{display_name}: #{readings.first} µm"
        else
          "#{display_name}: #{mean} µm (#{count} readings)"
        end
      end
    end

    summary_parts.join(', ')
  end

  # Get all measurements grouped by process type for display
  def thickness_measurements_by_type
    return {} unless has_thickness_measurements?

    measurements = measured_thicknesses['measurements'] || []
    measurements.group_by { |m| m['process_type'] }
  end

  # Check if all required thickness measurements are present
  def all_required_thickness_measurements_present?
    return true unless requires_thickness_measurements?

    required_treatments = get_required_treatments
    required_treatments.all? do |treatment|
      readings = get_thickness_readings(treatment[:treatment_id])
      readings.present? && readings.any?
    end
  end

  # Get missing thickness measurements
  def missing_thickness_measurements
    return [] unless requires_thickness_measurements?

    required_treatments = get_required_treatments
    required_treatments.filter_map do |treatment|
      readings = get_thickness_readings(treatment[:treatment_id])
      if readings.blank? || readings.empty?
        treatment
      end
    end
  end

  # ENP MEASUREMENT METHODS

  def treatment_is_enp?(process_type)
    process_type.to_s.start_with?('enp_') || process_type == 'electroless_nickel_plating'
  end

  def treatment_is_anodic?(process_type)
    %w[chromic_anodising hard_anodising standard_anodising].include?(process_type.to_s)
  end

  # Get ENP measurements for a treatment (returns array of 6 points)
  def get_enp_measurements(treatment_id)
    return [] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [] unless measurement

    measurement['enp_measurements'] || []
  end

  # Set ENP measurements for a treatment
  def set_enp_measurements(treatment_id, enp_data, treatment_info = {})
    # Initialize the structure if needed
    self.measured_thicknesses = { 'measurements' => [] } unless measured_thicknesses.is_a?(Hash)
    self.measured_thicknesses['measurements'] ||= []

    # Find existing measurement or create new one
    measurement = self.measured_thicknesses['measurements'].find { |m| m['treatment_id'] == treatment_id }

    if measurement
      # Update existing measurement
      if enp_data.blank? || (enp_data.is_a?(Array) && enp_data.empty?)
        # Remove measurement if data is blank
        self.measured_thicknesses['measurements'].reject! { |m| m['treatment_id'] == treatment_id }
      else
        measurement['enp_measurements'] = enp_data
      end
    elsif enp_data.present?
      # Add new measurement
      new_measurement = {
        'treatment_id' => treatment_id,
        'process_type' => treatment_info[:process_type],
        'enp_type' => treatment_info[:enp_type],
        'display_name' => treatment_info[:display_name],
        'enp_measurements' => enp_data
      }
      self.measured_thicknesses['measurements'] << new_measurement
    end

    true
  rescue => e
    Rails.logger.error "Error setting ENP measurements: #{e.message}"
    false
  end

  # Check if a treatment has ENP measurements
  def has_enp_measurements?(treatment_id)
    measurements = get_enp_measurements(treatment_id)
    measurements.present? && measurements.any? { |m| m['growth_um'].present? }
  end

  # Get ENP statistics for a treatment
  def get_enp_statistics(treatment_id)
    measurements = get_enp_measurements(treatment_id)
    valid_growths = measurements.map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }

    return nil if valid_growths.empty?

    {
      count: valid_growths.count,
      mean: calculate_mean(valid_growths),
      min: valid_growths.min,
      max: valid_growths.max
    }
  end

  def self.next_number
    Sequence.next_value('release_note_number')
  end

  def can_be_deleted?
    invoice_item.blank?
  end

  def can_create_ncr?
    !voided && (quantity_accepted > 0 || quantity_rejected > 0)
  end

  def has_open_ncrs?
    external_ncrs.active.exists?
  end

  def latest_ncr
    external_ncrs.recent.first
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.quantity_accepted = 0 if quantity_accepted.nil?
    self.quantity_rejected = 0 if quantity_rejected.nil?
    self.no_invoice = false if no_invoice.nil?
  end

  def set_date
    self.date = Date.current if date.blank?
  end

  def assign_next_number
    self.number = self.class.next_number if number.blank?
  end

  def total_quantity_must_be_positive
    if total_quantity <= 0
      errors.add(:base, "Total quantity (accepted + rejected) must be greater than 0")
    end
  end

  def quantity_available_for_release
    return unless works_order && total_quantity

    current_quantity = persisted? ? quantity_accepted_was + quantity_rejected_was : 0
    additional_quantity = total_quantity - current_quantity

    if additional_quantity > 0 && additional_quantity > works_order.quantity_remaining
      errors.add(:base,
        "You are trying to release #{additional_quantity} parts, " \
        "but only #{works_order.quantity_remaining} are available for release."
      )
    end
  end

  def validate_thickness_measurements
    return unless requires_thickness_measurements?

    required_treatments = get_required_treatments

    required_treatments.each do |treatment|
      display_name = treatment[:display_name] || treatment[:process_type].humanize.titleize

      # Check if this is an ENP or anodic treatment
      if treatment_is_enp?(treatment[:process_type])
        # Validate ENP measurements
        enp_measurements = get_enp_measurements(treatment[:treatment_id])

        if enp_measurements.blank? || enp_measurements.empty?
          errors.add(:measured_thicknesses, "#{display_name} ENP measurements are required for aerospace/defense parts")
        else
          # Validate that all 6 points have valid measurements
          enp_measurements.each do |measurement|
            point = measurement['point']
            growth = measurement['growth_um']

            if growth.nil?
              errors.add(:measured_thicknesses, "#{display_name} point #{point} is incomplete")
            elsif growth < 0
              errors.add(:measured_thicknesses, "#{display_name} point #{point} has negative growth (#{growth}µm)")
            elsif growth > 1000
              errors.add(:measured_thicknesses, "#{display_name} point #{point} seems unrealistically high (#{growth}µm)")
            end
          end

          # Ensure we have all 6 points
          if enp_measurements.count < 6
            errors.add(:measured_thicknesses, "#{display_name} requires all 6 measurement points (A-F)")
          end
        end
      else
        # Validate anodic thickness readings
        readings = get_thickness_readings(treatment[:treatment_id])

        if readings.blank? || readings.empty?
          errors.add(:measured_thicknesses, "#{display_name} thickness measurement is required for aerospace/defense parts")
        else
          # Validate each reading
          readings.each_with_index do |reading, index|
            if reading <= 0
              errors.add(:measured_thicknesses, "#{display_name} reading #{index + 1} must be greater than 0")
            elsif reading > 1000
              errors.add(:measured_thicknesses, "#{display_name} reading #{index + 1} seems unrealistically high (>1000µm)")
            end
          end
        end
      end
    end
  end

  def update_works_order_quantity_released
    works_order&.calculate_quantity_released!
  end

  # Generate a unique treatment ID based on treatment characteristics
  def generate_treatment_id(treatment, index)
    id_components = [
      treatment["type"],
      treatment["target_thickness"],
      treatment["selected_jig_type"],
      index
    ].compact

    Digest::SHA256.hexdigest(id_components.join('|'))[0, 12]
  end

  # Generate a display name for a treatment
  def generate_display_name(treatment)
    process_name = treatment["type"].humanize.gsub('_', ' ').titleize
    # REMOVED: target thickness from display name as it's often inaccurate
    process_name
  end

  # Process thickness value(s) - handles both single values and arrays
  def process_thickness_readings(value_or_readings)
    if value_or_readings.is_a?(Array)
      # Array of readings from Elcometer
      value_or_readings.map { |v| process_single_reading(v) }.compact
    elsif value_or_readings.is_a?(String)
      # Could be JSON array string from form
      begin
        parsed = JSON.parse(value_or_readings)
        if parsed.is_a?(Array)
          parsed.map { |v| process_single_reading(v) }.compact
        else
          [process_single_reading(value_or_readings)].compact
        end
      rescue JSON::ParserError
        # Not JSON, treat as single value
        [process_single_reading(value_or_readings)].compact
      end
    else
      # Single value (backward compatibility)
      [process_single_reading(value_or_readings)].compact
    end
  end

  # Process a single reading value
  def process_single_reading(value)
    return nil if value.blank?

    float_value = Float(value.to_s)
    return nil if float_value <= 0

    # Round to 1 decimal place (Elcometer precision)
    (float_value * 10).round / 10.0
  rescue ArgumentError, TypeError
    nil
  end

  # Calculate mean from array of readings
  def calculate_mean(readings)
    return nil if readings.empty?
    sum = readings.sum
    mean = sum / readings.count.to_f
    # Round to 1 decimal place
    (mean * 10).round / 10.0
  end

  def saved_change_to_invoicing_status?
    saved_change_to_quantity_accepted? || saved_change_to_voided? || saved_change_to_no_invoice?
  end

  def update_customer_order_uninvoiced_count
    return unless works_order&.customer_order_id
    update_counts_for_customer_order_id(works_order.customer_order_id)
  end

  def customer_order_id
    works_order&.customer_order_id
  end

  def customer_order_id_previously_was
    nil
  end
end
