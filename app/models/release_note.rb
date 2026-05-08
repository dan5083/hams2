# app/models/release_note.rb - Updated to support multiple batches per treatment
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

  # ==========================================================================
  # THICKNESS MEASUREMENT METHODS
  # Supports multi-batch measurements (audit requirement: 8 readings per batch).
  #
  # Data structure (new format):
  #   measured_thicknesses = {
  #     'measurements' => [
  #       {
  #         'treatment_id' => 'abc123',
  #         'process_type' => 'hard_anodising',
  #         'display_name' => 'Hard Anodising',
  #         'target_thickness' => 25,
  #         'batches' => [
  #           { 'batch_number' => 1, 'readings' => [70.5, 70.7, ...] },   # anodic
  #           { 'batch_number' => 2, 'readings' => [71.0, 70.8, ...] }
  #         ]
  #       },
  #       {
  #         'treatment_id' => 'def456',
  #         'process_type' => 'electroless_nickel_plating',
  #         'batches' => [
  #           { 'batch_number' => 1, 'enp_measurements' => [{point: 'A', ...}, ...] },
  #           { 'batch_number' => 2, 'enp_measurements' => [...] }
  #         ]
  #       }
  #     ]
  #   }
  #
  # Legacy format (single batch, no 'batches' key) is read transparently
  # and migrated to the new format on next save.
  # ==========================================================================

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

  # -------------------------------------------------------------------------
  # Batch count helpers
  # -------------------------------------------------------------------------

  # Returns how many batches are recorded for a treatment (minimum 1 if any data present).
  def get_batch_count(treatment_id)
    return 1 unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return 1 unless measurement

    if measurement['batches'].is_a?(Array) && measurement['batches'].any?
      measurement['batches'].count
    else
      1 # Legacy single-batch data
    end
  end

  # -------------------------------------------------------------------------
  # Anodic thickness readings (per-batch)
  # -------------------------------------------------------------------------

  # Returns readings for a specific batch number. Returns [] if not found.
  # Falls back to legacy flat 'readings' for batch 1 on old records.
  def get_thickness_readings_for_batch(treatment_id, batch_number)
    return [] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [] unless measurement

    if measurement['batches'].is_a?(Array)
      batch = measurement['batches'].find { |b| b['batch_number'] == batch_number }
      batch ? (batch['readings'] || []) : []
    elsif batch_number == 1
      # Legacy: flat readings array counts as batch 1
      measurement['readings'] || []
    else
      []
    end
  end

  # Returns ALL readings across all batches (for backwards-compatible callers).
  def get_thickness_readings(treatment_id)
    return [] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [] unless measurement

    if measurement['batches'].is_a?(Array)
      measurement['batches'].flat_map { |b| b['readings'] || [] }
    else
      measurement['readings'] || [] # Legacy
    end
  end

  # Returns mean thickness across all batches (backwards compat).
  def get_thickness_measurement(treatment_id)
    readings = get_thickness_readings(treatment_id)
    return nil if readings.empty?
    calculate_mean(readings)
  end

  # Returns statistics across all batches combined.
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

  # Returns per-batch statistics as an array of hashes.
  def get_thickness_statistics_by_batch(treatment_id)
    batch_count = get_batch_count(treatment_id)
    (1..batch_count).filter_map do |batch_number|
      readings = get_thickness_readings_for_batch(treatment_id, batch_number)
      next if readings.empty?
      {
        batch_number: batch_number,
        count: readings.count,
        mean: calculate_mean(readings),
        min: readings.min,
        max: readings.max,
        readings: readings
      }
    end
  end

  # Accepts either:
  #   - An array of batch hashes: [{ 'batch_number' => 1, 'readings' => [...] }, ...]
  #   - A flat readings array (legacy): [70.5, 70.7, ...]  → stored as batch 1
  def set_thickness_measurement(treatment_id, batches_or_readings, treatment_info = {})
    self.measured_thicknesses = { 'measurements' => [] } unless measured_thicknesses.is_a?(Hash)
    self.measured_thicknesses['measurements'] ||= []

    measurement = self.measured_thicknesses['measurements'].find { |m| m['treatment_id'] == treatment_id }

    processed_batches = normalise_anodic_batches(batches_or_readings)

    if measurement
      if processed_batches.empty?
        self.measured_thicknesses['measurements'].reject! { |m| m['treatment_id'] == treatment_id }
      else
        measurement['batches'] = processed_batches
        measurement.delete('readings') # Remove legacy flat key
      end
    elsif processed_batches.any?
      new_measurement = {
        'treatment_id'     => treatment_id,
        'process_type'     => treatment_info[:process_type],
        'target_thickness' => treatment_info[:target_thickness] || 0,
        'display_name'     => treatment_info[:display_name],
        'batches'          => processed_batches
      }
      self.measured_thicknesses['measurements'] << new_measurement
    end

    true
  rescue ArgumentError
    false
  end

  # -------------------------------------------------------------------------
  # ENP measurements (per-batch)
  # -------------------------------------------------------------------------

  # Returns ENP measurements for a specific batch.
  def get_enp_measurements_for_batch(treatment_id, batch_number)
    return [] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [] unless measurement

    if measurement['batches'].is_a?(Array)
      batch = measurement['batches'].find { |b| b['batch_number'] == batch_number }
      batch ? (batch['enp_measurements'] || []) : []
    elsif batch_number == 1
      measurement['enp_measurements'] || [] # Legacy
    else
      []
    end
  end

  # Returns batch-1 ENP measurements (backwards compat).
  def get_enp_measurements(treatment_id)
    get_enp_measurements_for_batch(treatment_id, 1)
  end

  # Returns per-batch ENP statistics as an array of hashes.
  def get_enp_statistics_by_batch(treatment_id)
    batch_count = get_batch_count(treatment_id)
    (1..batch_count).filter_map do |batch_number|
      measurements = get_enp_measurements_for_batch(treatment_id, batch_number)
      valid_growths = measurements.map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }
      next if valid_growths.empty?
      {
        batch_number: batch_number,
        count: valid_growths.count,
        mean: calculate_mean(valid_growths),
        min: valid_growths.min,
        max: valid_growths.max,
        enp_measurements: measurements
      }
    end
  end

  # Accepts either:
  #   - An array of batch hashes: [{ 'batch_number' => 1, 'enp_measurements' => [...] }, ...]
  #   - A flat ENP array (legacy): [{ 'point' => 'A', ... }, ...]  → stored as batch 1
  def set_enp_measurements(treatment_id, batches_or_enp_data, treatment_info = {})
    self.measured_thicknesses = { 'measurements' => [] } unless measured_thicknesses.is_a?(Hash)
    self.measured_thicknesses['measurements'] ||= []

    measurement = self.measured_thicknesses['measurements'].find { |m| m['treatment_id'] == treatment_id }

    processed_batches = normalise_enp_batches(batches_or_enp_data)

    if measurement
      if processed_batches.empty?
        self.measured_thicknesses['measurements'].reject! { |m| m['treatment_id'] == treatment_id }
      else
        measurement['batches'] = processed_batches
        measurement.delete('enp_measurements') # Remove legacy flat key
      end
    elsif processed_batches.any?
      new_measurement = {
        'treatment_id'   => treatment_id,
        'process_type'   => treatment_info[:process_type],
        'enp_type'       => treatment_info[:enp_type],
        'display_name'   => treatment_info[:display_name],
        'batches'        => processed_batches
      }
      self.measured_thicknesses['measurements'] << new_measurement
    end

    true
  rescue => e
    Rails.logger.error "Error setting ENP measurements: #{e.message}"
    false
  end

  def has_enp_measurements?(treatment_id)
    batch_count = get_batch_count(treatment_id)
    (1..batch_count).any? do |batch_number|
      measurements = get_enp_measurements_for_batch(treatment_id, batch_number)
      measurements.present? && measurements.any? { |m| m['growth_um'].present? }
    end
  end

  # Returns combined ENP statistics across all batches.
  def get_enp_statistics(treatment_id)
    all_growths = (1..get_batch_count(treatment_id)).flat_map do |batch_number|
      get_enp_measurements_for_batch(treatment_id, batch_number)
        .map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }
    end

    return nil if all_growths.empty?

    {
      count: all_growths.count,
      mean: calculate_mean(all_growths),
      min: all_growths.min,
      max: all_growths.max
    }
  end

  # -------------------------------------------------------------------------
  # General measurement helpers
  # -------------------------------------------------------------------------

  def has_thickness_measurements?
    return false unless measured_thicknesses.is_a?(Hash)
    measurements = measured_thicknesses['measurements']
    return false unless measurements.present?

    measurements.any? do |m|
      if m['batches'].is_a?(Array) && m['batches'].any?
        m['batches'].any? do |b|
          (b['readings'].present? && b['readings'].any?) ||
          (b['enp_measurements'].present? && b['enp_measurements'].any?)
        end
      else
        (m['readings'].present? && m['readings'].any?) ||
        (m['enp_measurements'].present? && m['enp_measurements'].any?)
      end
    end
  end

  def thickness_measurements_summary
    return nil unless has_thickness_measurements?

    measurements = measured_thicknesses['measurements'] || []
    summary_parts = measurements.filter_map do |measurement|
      display_name = measurement['display_name'] || measurement['process_type'].humanize.titleize

      if measurement['batches'].is_a?(Array) && measurement['batches'].any?
        batch_count = measurement['batches'].count
        batch_label = batch_count > 1 ? "#{batch_count} batches" : "1 batch"

        # Detect type from first batch's keys
        if measurement['batches'].first&.key?('enp_measurements')
          all_growths = measurement['batches'].flat_map { |b|
            (b['enp_measurements'] || []).map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }
          }
          next if all_growths.empty?
          mean = calculate_mean(all_growths)
          "#{display_name}: #{mean} µm growth (#{batch_label}, #{all_growths.count} points)"
        else
          all_readings = measurement['batches'].flat_map { |b| b['readings'] || [] }
          next if all_readings.empty?
          mean = calculate_mean(all_readings)
          "#{display_name}: #{mean} µm (#{batch_label}, #{all_readings.count} readings)"
        end
      elsif measurement['enp_measurements'].present? && measurement['enp_measurements'].any?
        valid_growths = measurement['enp_measurements'].map { |m| m['growth_um'] }.compact.select { |g| g >= 0 }
        next if valid_growths.empty?
        mean = calculate_mean(valid_growths)
        "#{display_name}: #{mean} µm growth (#{valid_growths.count}/6 points)"
      elsif measurement['readings'].present? && measurement['readings'].any?
        readings = measurement['readings']
        mean = calculate_mean(readings)
        count = readings.count
        count == 1 ? "#{display_name}: #{readings.first} µm" : "#{display_name}: #{mean} µm (#{count} readings)"
      end
    end

    summary_parts.join(', ')
  end

  def thickness_measurements_by_type
    return {} unless has_thickness_measurements?
    measurements = measured_thicknesses['measurements'] || []
    measurements.group_by { |m| m['process_type'] }
  end

  def all_required_thickness_measurements_present?
    return true unless requires_thickness_measurements?

    required_treatments = get_required_treatments
    required_treatments.all? do |treatment|
      batch_count = get_batch_count(treatment[:treatment_id])
      (1..batch_count).all? do |batch_number|
        if treatment_is_enp?(treatment[:process_type])
          measurements = get_enp_measurements_for_batch(treatment[:treatment_id], batch_number)
          measurements.present? && measurements.any?
        else
          readings = get_thickness_readings_for_batch(treatment[:treatment_id], batch_number)
          readings.present? && readings.any?
        end
      end
    end
  end

  def missing_thickness_measurements
    return [] unless requires_thickness_measurements?

    required_treatments = get_required_treatments
    required_treatments.filter_map do |treatment|
      readings = get_thickness_readings(treatment[:treatment_id])
      treatment if readings.blank? || readings.empty?
    end
  end

  # -------------------------------------------------------------------------
  # ENP type helpers
  # -------------------------------------------------------------------------

  def treatment_is_enp?(process_type)
    process_type.to_s.start_with?('enp_') || process_type == 'electroless_nickel_plating'
  end

  def treatment_is_anodic?(process_type)
    %w[chromic_anodising hard_anodising standard_anodising].include?(process_type.to_s)
  end

  # -------------------------------------------------------------------------
  # Sequence / lifecycle
  # -------------------------------------------------------------------------

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
      batch_count  = get_batch_count(treatment[:treatment_id])

      if treatment_is_enp?(treatment[:process_type])
        (1..batch_count).each do |batch_number|
          batch_prefix = batch_count > 1 ? "Batch #{batch_number} - " : ""
          enp_measurements = get_enp_measurements_for_batch(treatment[:treatment_id], batch_number)

          if enp_measurements.blank? || enp_measurements.empty?
            errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} ENP measurements are required for aerospace/defense parts")
          else
            enp_measurements.each do |m|
              point  = m['point']
              growth = m['growth_um']
              if growth.nil?
                errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} point #{point} is incomplete")
              elsif growth < 0
                errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} point #{point} has negative growth (#{growth}µm)")
              elsif growth > 1000
                errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} point #{point} seems unrealistically high (#{growth}µm)")
              end
            end

            if enp_measurements.count < 6
              errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} requires all 6 measurement points (A-F)")
            end
          end
        end
      else
        # Anodic
        (1..batch_count).each do |batch_number|
          batch_prefix = batch_count > 1 ? "Batch #{batch_number} - " : ""
          readings = get_thickness_readings_for_batch(treatment[:treatment_id], batch_number)

          if readings.blank? || readings.empty?
            errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} thickness measurement is required for aerospace/defense parts")
          else
            readings.each_with_index do |reading, index|
              if reading <= 0
                errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} reading #{index + 1} must be greater than 0")
              elsif reading > 1000
                errors.add(:measured_thicknesses, "#{batch_prefix}#{display_name} reading #{index + 1} seems unrealistically high (>1000µm)")
              end
            end
          end
        end
      end
    end
  end

  def update_works_order_quantity_released
    works_order&.calculate_quantity_released!
  end

  def generate_treatment_id(treatment, index)
    id_components = [
      treatment["type"],
      treatment["target_thickness"],
      treatment["selected_jig_type"],
      index
    ].compact
    Digest::SHA256.hexdigest(id_components.join('|'))[0, 12]
  end

  def generate_display_name(treatment)
    treatment["type"].humanize.gsub('_', ' ').titleize
  end

  # Normalises input to an array of { 'batch_number' => n, 'readings' => [...] }
  def normalise_anodic_batches(input)
    batches = if input.is_a?(Array) && input.first.is_a?(Hash) && input.first.key?('batch_number')
      input.map do |b|
        {
          'batch_number' => b['batch_number'].to_i,
          'readings'     => process_thickness_readings(b['readings'] || [])
        }
      end
    elsif input.is_a?(Array)
      readings = process_thickness_readings(input)
      readings.any? ? [{ 'batch_number' => 1, 'readings' => readings }] : []
    else
      []
    end

    batches.reject { |b| b['readings'].empty? }
  end

  # Normalises input to an array of { 'batch_number' => n, 'enp_measurements' => [...] }
  def normalise_enp_batches(input)
    batches = if input.is_a?(Array) && input.first.is_a?(Hash) && input.first.key?('batch_number')
      input
    elsif input.is_a?(Array)
      input.any? ? [{ 'batch_number' => 1, 'enp_measurements' => input }] : []
    else
      []
    end

    batches.reject { |b| (b['enp_measurements'] || []).empty? }
  end

  def process_thickness_readings(value_or_readings)
    if value_or_readings.is_a?(Array)
      value_or_readings.map { |v| process_single_reading(v) }.compact
    elsif value_or_readings.is_a?(String)
      begin
        parsed = JSON.parse(value_or_readings)
        if parsed.is_a?(Array)
          parsed.map { |v| process_single_reading(v) }.compact
        else
          [process_single_reading(value_or_readings)].compact
        end
      rescue JSON::ParserError
        [process_single_reading(value_or_readings)].compact
      end
    else
      [process_single_reading(value_or_readings)].compact
    end
  end

  def process_single_reading(value)
    return nil if value.blank?
    float_value = Float(value.to_s)
    return nil if float_value <= 0
    (float_value * 10).round / 10.0
  rescue ArgumentError, TypeError
    nil
  end

  def calculate_mean(readings)
    return nil if readings.empty?
    sum  = readings.sum
    mean = sum / readings.count.to_f
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
