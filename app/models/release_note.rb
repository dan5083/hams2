# app/models/release_note.rb - Updated to support multiple batches per treatment
# and MIL-PRF-8625F Type III NADCAP sample-plan thickness measurements.
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
  validate :validate_process_record_coverage, unless: :invoiced?

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
  # Paperless aero/defence: thickness was recorded in-line on the process
  # record; the RN records which (op, batch) rows it certifies (see below).
  before_validation :assign_certified_batches, if: -> { new_record? && inline_thickness_record? }
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

  # NADCAP sample plan (MIL-PRF-8625F Type III hard anodise) - rules live in
  # FilmThickness (shared with the process record); these stay as thin
  # wrappers for existing callers (form, JS values, controller).
  def self.nadcap_sample_size(parts_per_batch)
    FilmThickness.nadcap_sample_size(parts_per_batch)
  end

  def self.nadcap_total_readings(parts_per_batch)
    FilmThickness.nadcap_total_readings(parts_per_batch)
  end

  def self.nadcap_readings_plan(parts_per_batch)
    FilmThickness.nadcap_readings_plan(parts_per_batch)
  end

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
  # Supports multi-batch measurements.
  #
  # Data structure:
  #   measured_thicknesses = {
  #     'measurements' => [
  #       {
  #         'treatment_id' => 'abc123',
  #         'process_type' => 'hard_anodising',
  #         'display_name' => 'Hard Anodising',
  #         'target_thickness' => 25,
  #         'batches' => [
  #           # Standard anodic batch (8 readings):
  #           { 'batch_number' => 1, 'readings' => [70.5, 70.7, ...] },
  #
  #           # NADCAP sample-plan batch (MIL-PRF-8625F Type III):
  #           # Total readings = max(8, sample_size), spread across the parts
  #           # (see nadcap_readings_plan). e.g. lot 300 -> 16 parts x 1 reading.
  #           { 'batch_number' => 2,
  #             'parts_per_batch' => 300,
  #             'parts' => [
  #               { 'part_label' => 'B2p1', 'readings' => [70.5] },  # per-part count from plan
  #               { 'part_label' => 'B2p2', 'readings' => [...] },
  #               ...                                                 # sample_size parts total
  #             ],
  #             'readings' => [...flattened nadcap_total_readings readings...]
  #           }
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
      nadcap_spec     = nadcap_sampling_specification?

      measurable_treatments = treatments_data.select do |treatment|
        MEASURABLE_PROCESS_TYPES.include?(treatment["type"])
      end

      measurable_treatments.map.with_index do |treatment, index|
        {
          treatment_id:             generate_treatment_id(treatment, index),
          process_type:             treatment["type"],
          target_thickness:         treatment["target_thickness"] || 0,
          display_name:             generate_display_name(treatment),
          # NADCAP trigger: works_order spec contains "PRF" AND "III"
          # AND the treatment itself is hard anodising
          requires_nadcap_sampling: nadcap_spec && treatment["type"] == "hard_anodising"
        }
      end
    rescue => e
      Rails.logger.error "Error getting required treatments for thickness measurement: #{e.message}"
      []
    end
  end

  # Detects if works_order.specification triggers MIL-PRF-8625F Type III NADCAP
  # sampling. Matches "PRF" anywhere and "III" as a whole token (word-bounded)
  # so we don't false-positive on "IIIA" etc.
  def nadcap_sampling_specification?
    FilmThickness.nadcap_sampling_specification?(works_order&.specification)
  end

  # -------------------------------------------------------------------------
  # In-line (process record) thickness - paperless aero/defence
  #
  # The readings live on the works order's process record and are not copied
  # here. What the RN owns is ATTRIBUTION: which (op, batch) rows it
  # certifies. That is the one thing not derivable later - if it were
  # derived at read time, a batch signed off next week (or freed by voiding a
  # later RN) would migrate onto this RN's reprint.
  #
  # Stored in measured_thicknesses as
  #   { "source" => "process_record", "certified_batches" => [{ "position" => 14, "batch" => "1" }, ...] }
  # and the reader below expands that into the same measurements/batches
  # structure the form always produced, so show page, PDF and every helper
  # in this file see one shape wherever the readings were captured.
  #
  # At creation the RN takes every certified row that no earlier ACTIVE RN
  # of this WO already holds: a partial release carries the batches
  # finished so far, the next RN carries the ones finished since, and
  # voiding an RN hands its batches to the next one.
  # -------------------------------------------------------------------------
  def inline_thickness_record?
    works_order.present? && works_order.inline_thickness_record?
  end

  def self.certified_batch_refs?(raw)
    raw.is_a?(Hash) && raw['source'] == 'process_record' && raw.key?('certified_batches')
  end

  # Raw column value (the refs, for an in-line RN); the public reader expands.
  def measured_thicknesses_raw
    self[:measured_thicknesses]
  end

  def measured_thicknesses
    raw = self[:measured_thicknesses]
    return raw unless self.class.certified_batch_refs?(raw)
    refs = raw['certified_batches'] || []
    if @expanded_for != refs
      @expanded_for = refs
      @expanded = expand_certified_batches(refs)
    end
    @expanded
  end

  def certified_batch_refs
    raw = self[:measured_thicknesses]
    self.class.certified_batch_refs?(raw) ? (raw['certified_batches'] || []) : []
  end

  # (position, batch) rows already held by earlier active RNs of THIS works
  # order. Scoped to the WO, not the group: on a grouped record a batch is
  # the whole tank load, so every member's CofC references it - only a later
  # RN of the same WO must not repeat it.
  def batches_certified_elsewhere
    scope = works_order.release_notes.active
    scope = scope.where.not(id: id) if persisted?
    scope.flat_map { |rn| rn.certified_batch_refs.map { |r| [r['position'].to_i, r['batch'].to_s] } }.to_set
  end

  def assign_certified_batches
    return unless inline_thickness_record?
    taken = batches_certified_elsewhere
    refs = works_order.certified_thickness_batches.filter_map do |c|
      pos = c[:op]['position'].to_i
      next nil if taken.include?([pos, c[:batch]])
      { 'position' => pos, 'batch' => c[:batch] }
    end.sort_by { |r| [r['batch'].to_i, r['position']] }
    self.measured_thicknesses = { 'source' => 'process_record', 'certified_batches' => refs }
  end

  # Console use: re-attribute an un-invoiced RN after a late sign-off.
  def reassign_certified_batches!
    assign_certified_batches
    save!
  end

  # Expand refs into the measurements structure, reading rows off the record.
  # Foil ops appear once per anodic treatment, in treatment order
  # (Part#add_treatment_cycle), as do ENP ops - so the i-th op of a kind is
  # the i-th treatment of that kind.
  def expand_certified_batches(refs)
    return { 'measurements' => [], 'source' => 'process_record' } if works_order.nil?

    owner      = works_order.process_record_owner
    ops        = owner.film_thickness_ops
    treatments = get_required_treatments
    anodic_tr  = treatments.select { |t| treatment_is_anodic?(t[:process_type]) }
    enp_tr     = treatments.select { |t| treatment_is_enp?(t[:process_type]) }
    anodic_ops = ops.select { |op| FilmThickness.field_for(op) == FilmThickness::ANODIC_FIELD }
    enp_ops    = ops.select { |op| FilmThickness.field_for(op) == FilmThickness::ENP_FIELD }
    refs_by_pos = refs.group_by { |r| r['position'].to_i }

    batches_for = lambda do |op, treatment|
      section = owner.section_for_op(op)
      rows    = op['ocv_readings'] || {}
      (refs_by_pos[op['position'].to_i] || []).filter_map do |r|
        key = r['batch'].to_s
        FilmThickness.batch_from_row(op, rows[key] || {}, key,
                                     parts_per_batch: owner.section_batch_qty(section, key),
                                     nadcap: treatment[:requires_nadcap_sampling])
      end.sort_by { |b| b['batch_number'] }
    end

    measurements = []
    anodic_ops.each_with_index do |op, i|
      treatment = anodic_tr[i] or next
      batches   = batches_for.call(op, treatment)
      next if batches.empty?
      measurements << {
        'treatment_id'     => treatment[:treatment_id],
        'process_type'     => treatment[:process_type],
        'target_thickness' => treatment[:target_thickness] || 0,
        'display_name'     => treatment[:display_name],
        'batches'          => batches
      }
    end
    enp_ops.each_with_index do |op, i|
      treatment = enp_tr[i] or next
      batches   = batches_for.call(op, treatment)
      next if batches.empty?
      measurements << {
        'treatment_id' => treatment[:treatment_id],
        'process_type' => treatment[:process_type],
        'enp_type'     => treatment[:process_type],
        'display_name' => treatment[:display_name],
        'batches'      => batches
      }
    end
    { 'measurements' => measurements, 'source' => 'process_record' }
  end

  # Actual batch numbers recorded for a treatment. Process-record snapshots
  # carry WO batch numbers, which need not start at 1 or be contiguous (RN2
  # may certify batches 3-4 only) - iterate these, never (1..count).
  def batch_numbers(treatment_id)
    return [1] unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return [1] unless measurement
    batches = measurement['batches']
    return [1] unless batches.is_a?(Array) && batches.any?
    batches.map { |b| b['batch_number'].to_i }.sort
  end

  # Generic batch fetcher - returns the raw batch hash (legacy or NADCAP shape),
  # or an empty hash if not found.
  def get_batch(treatment_id, batch_number)
    return {} unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    return {} unless measurement

    batches = measurement['batches']
    return {} unless batches.is_a?(Array)

    batches.find { |b| b['batch_number'].to_i == batch_number.to_i } || {}
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
    batch_numbers(treatment_id).filter_map do |batch_number|
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
  #     (may also include NADCAP keys 'parts_per_batch' and 'parts')
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
  # NADCAP sample-plan helpers (per-batch)
  # -------------------------------------------------------------------------

  # Returns the structured NADCAP data for a batch:
  #   { parts_per_batch: 300, parts: [{ 'part_label' => 'B1p1', 'readings' => [...] }, ...] }
  def get_nadcap_data_for_batch(treatment_id, batch_number)
    batch = get_batch(treatment_id, batch_number)
    {
      parts_per_batch: batch['parts_per_batch'],
      parts:           batch['parts'] || []
    }
  end

  # Serialised JSON string for the form's hidden field. Returns "" if no data yet.
  def get_nadcap_json_for_batch(treatment_id, batch_number)
    batch = get_batch(treatment_id, batch_number)
    return "" if batch.empty? || batch['parts_per_batch'].blank?
    {
      parts_per_batch: batch['parts_per_batch'],
      parts:           batch['parts'] || []
    }.to_json
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
    batch_numbers(treatment_id).filter_map do |batch_number|
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
    batch_numbers(treatment_id).any? do |batch_number|
      measurements = get_enp_measurements_for_batch(treatment_id, batch_number)
      measurements.present? && measurements.any? { |m| m['growth_um'].present? }
    end
  end

  # Returns combined ENP statistics across all batches.
  def get_enp_statistics(treatment_id)
    all_growths = batch_numbers(treatment_id).flat_map do |batch_number|
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
      batch_numbers(treatment[:treatment_id]).all? do |batch_number|
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

  # ---------------------------------------------------------------------------
  # Thickness validation. Two regimes:
  #   - in-line (paperless): readings were validated at sign-off on the
  #     process record and coverage is enforced by
  #     validate_process_record_coverage below - nothing extra here.
  #   - form-captured: validate the posted sets against the same rules
  #     (FilmThickness) the process record applies.
  # ---------------------------------------------------------------------------
  def validate_thickness_measurements
    return unless requires_thickness_measurements?
    return if inline_thickness_record?

    get_required_treatments.each do |treatment|
      display_name = treatment[:display_name] || treatment[:process_type].humanize.titleize
      numbers = batch_numbers(treatment[:treatment_id])
      numbers.each do |batch_number|
        prefix = numbers.size > 1 ? "Batch #{batch_number} - " : ""
        batch  = get_batch(treatment[:treatment_id], batch_number)

        problems =
          if treatment_is_enp?(treatment[:process_type])
            FilmThickness.enp_errors(get_enp_measurements_for_batch(treatment[:treatment_id], batch_number))
          elsif treatment[:requires_nadcap_sampling]
            FilmThickness.nadcap_errors(batch, batch['parts_per_batch'])
          else
            FilmThickness.anodic_errors(get_thickness_readings_for_batch(treatment[:treatment_id], batch_number))
          end

        problems.each { |e| errors.add(:measured_thicknesses, "#{prefix}#{display_name} #{e}") }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Paperless release rule: to release x parts, the process record must show
  # a complete sign-off through-line at least x wide (every WO-scoped op
  # signed; in every section, batches signed on every op summing to >= x),
  # counting everything already released against the record. Rejected parts
  # count as released - they went through the tanks regardless.
  # ---------------------------------------------------------------------------
  def validate_process_record_coverage
    return unless works_order&.paperless_record?
    certified = works_order.signed_off_quantity
    released  = works_order.released_quantity_against_record(except: self) + total_quantity
    return if certified >= released

    errors.add(:base,
      "The process record certifies #{certified} part(s) end to end, but #{released} would have " \
      "been released against it. Sign off the remaining operation(s)/batch(es) on " \
      "WO#{works_order.number}#{works_order.grouped? ? "'s process record" : ''} before releasing.")
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

  # Normalises input to an array of batch hashes. Each batch hash is at minimum:
  #   { 'batch_number' => n, 'readings' => [...] }
  # NADCAP batches additionally carry:
  #   { 'parts_per_batch' => n, 'parts' => [{ 'part_label' => ..., 'readings' => [...] }, ...] }
  def normalise_anodic_batches(input)
    batches = if input.is_a?(Array) && input.first.is_a?(Hash) && input.first.key?('batch_number')
      input.map do |b|
        hash = {
          'batch_number' => b['batch_number'].to_i,
          'readings'     => process_thickness_readings(b['readings'] || [])
        }

        # Preserve NADCAP sampling keys when present
        if b['parts_per_batch'].present?
          hash['parts_per_batch'] = b['parts_per_batch'].to_i
        end

        if b['parts'].is_a?(Array)
          hash['parts'] = b['parts'].map.with_index do |part, idx|
            {
              'part_label' => part['part_label'].presence || "p#{idx + 1}",
              'readings'   => process_thickness_readings(part['readings'] || [])
            }
          end
        end

        hash
      end
    elsif input.is_a?(Array)
      readings = process_thickness_readings(input)
      readings.any? ? [{ 'batch_number' => 1, 'readings' => readings }] : []
    else
      []
    end

    # A batch is empty only if it has neither flat readings nor sampled parts
    batches.reject { |b| (b['readings'] || []).empty? && (b['parts'] || []).empty? }
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
