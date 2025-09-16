# app/models/release_note.rb - Updated to allow post-invoice editing of remarks and quantities
require 'digest/sha2'

class ReleaseNote < ApplicationRecord
  belongs_to :works_order
  belongs_to :issued_by, class_name: 'User'
  has_one :invoice_item, dependent: :nullify

  validates :date, presence: true
  validates :quantity_accepted, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_rejected, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :total_quantity_must_be_positive
  validate :quantity_available_for_release, unless: :invoiced? # Skip quantity validation for invoiced release notes
  validate :validate_thickness_measurements

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }

  # VERIFIED: This scope correctly identifies release notes that need invoicing
  scope :requires_invoicing, -> {
    left_joins(:invoice_item)
      .where(invoice_items: { id: nil })          # No invoice item exists
      .where(voided: false)                       # Not voided
      .where('quantity_accepted > 0')             # Has accepted quantity
      .where.not(no_invoice: true)                # Not marked as no_invoice
  }

  # NEW: Additional useful scopes for invoicing workflow
  scope :invoiced, -> { joins(:invoice_item) }
  scope :ready_for_invoice, -> { requires_invoicing }  # Alias for clarity
  scope :recent, -> { order(number: :desc) }

  before_validation :set_date, if: :new_record?
  before_validation :assign_next_number, if: :new_record?
  after_initialize :set_defaults, if: :new_record?
  after_save :update_works_order_quantity_released, unless: :invoiced? # Skip works order quantity updates for invoiced release notes
  after_destroy :update_works_order_quantity_released

  # Process types that can have thickness measurements
  MEASURABLE_PROCESS_TYPES = %w[
    chromic_anodising
    electroless_nickel_plating
    hard_anodising
    standard_anodising
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
    # Always use the remarks field as the release statement
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

  # NEW: Enhanced editing capabilities for invoiced release notes
  def can_be_edited?
    !voided # Can edit as long as not voided, even if invoiced
  end

  def can_edit_quantities?
    invoiced? # Can edit quantities only if already invoiced (to prevent invoice impact)
  end

  def can_edit_remarks?
    true # Can always edit remarks (unless voided, handled by can_be_edited?)
  end

  # NEW: Enhanced invoicing status methods
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
      # For lot pricing, we need to calculate proportionally
      return 0 if works_order.quantity.zero?
      (quantity_accepted.to_f / works_order.quantity) * works_order.lot_price
    else
      0
    end
  end

  # NEW: Warning methods for post-invoice editing
  def editing_invoiced_warning
    return nil unless invoiced?
    "⚠️ This release note has been invoiced. Editing quantities will not affect the invoice amounts."
  end

  def show_invoice_impact_warning?
    invoiced? && (quantity_accepted_changed? || quantity_rejected_changed?)
  end

  # NEW THICKNESS MEASUREMENT METHODS - Support multiple measurements per treatment type

  def requires_thickness_measurements?
    return false unless works_order.part&.aerospace_defense?
    get_required_treatments.any?
  end

  def get_required_treatments
    return [] unless works_order.part

    begin
      # Get treatments directly from the part's stored customisation data
      treatments_data = works_order.part.send(:parse_treatments_data)

      # Filter for treatments that require thickness measurements
      measurable_treatments = treatments_data.select do |treatment|
        MEASURABLE_PROCESS_TYPES.include?(treatment["type"])
      end

      # Return treatment info with unique identifiers
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

  def get_thickness_measurement(treatment_id)
    return nil unless measured_thicknesses.is_a?(Hash)
    measurement = measured_thicknesses['measurements']&.find { |m| m['treatment_id'] == treatment_id }
    measurement&.dig('measured_thickness')
  end

  def set_thickness_measurement(treatment_id, value, treatment_info = {})
    # Initialize the structure if needed
    self.measured_thicknesses = { 'measurements' => [] } unless measured_thicknesses.is_a?(Hash)
    self.measured_thicknesses['measurements'] ||= []

    # Find existing measurement or create new one
    measurement = self.measured_thicknesses['measurements'].find { |m| m['treatment_id'] == treatment_id }

    if measurement
      # Update existing measurement
      if value.blank?
        # Remove measurement if value is blank
        self.measured_thicknesses['measurements'].reject! { |m| m['treatment_id'] == treatment_id }
      else
        measurement['measured_thickness'] = process_thickness_value(value)
      end
    elsif value.present?
      # Add new measurement
      new_measurement = {
        'treatment_id' => treatment_id,
        'process_type' => treatment_info[:process_type],
        'target_thickness' => treatment_info[:target_thickness] || 0,
        'display_name' => treatment_info[:display_name],
        'measured_thickness' => process_thickness_value(value)
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
    measurements.present? && measurements.any? { |m| m['measured_thickness'].present? }
  end

  def thickness_measurements_summary
    return nil unless has_thickness_measurements?

    measurements = measured_thicknesses['measurements'] || []
    summary_parts = measurements.filter_map do |measurement|
      thickness = measurement['measured_thickness']
      next unless thickness.present?

      display_name = measurement['display_name'] || measurement['process_type'].humanize.titleize
      "#{display_name}: #{thickness} µm"
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
      get_thickness_measurement(treatment[:treatment_id]).present?
    end
  end

  # Get missing thickness measurements
  def missing_thickness_measurements
    return [] unless requires_thickness_measurements?

    required_treatments = get_required_treatments
    required_treatments.filter_map do |treatment|
      if get_thickness_measurement(treatment[:treatment_id]).blank?
        treatment
      end
    end
  end

  def self.next_number
    Sequence.next_value('release_note_number')
  end

  def can_be_deleted?
    invoice_item.blank?
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

    # Calculate how much quantity this release note currently accounts for
    current_quantity = persisted? ? quantity_accepted_was + quantity_rejected_was : 0

    # Calculate the additional quantity this release note would account for
    additional_quantity = total_quantity - current_quantity

    # Only check if we're increasing the total quantity released
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
      thickness = get_thickness_measurement(treatment[:treatment_id])

      if thickness.blank?
        display_name = treatment[:display_name] || treatment[:process_type].humanize.titleize
        errors.add(:measured_thicknesses, "#{display_name} thickness measurement is required for aerospace/defense parts")
      elsif thickness <= 0
        display_name = treatment[:display_name] || treatment[:process_type].humanize.titleize
        errors.add(:measured_thicknesses, "#{display_name} thickness must be greater than 0")
      elsif thickness > 1000 # Sanity check - no coating should be > 1mm
        display_name = treatment[:display_name] || treatment[:process_type].humanize.titleize
        errors.add(:measured_thicknesses, "#{display_name} thickness seems unrealistically high (>1000µm)")
      end
    end
  end

  def update_works_order_quantity_released
    works_order&.calculate_quantity_released!
  end

  # Generate a unique treatment ID based on treatment characteristics
  def generate_treatment_id(treatment, index)
    # Create a deterministic ID based on treatment properties
    id_components = [
      treatment["type"],
      treatment["target_thickness"],
      treatment["selected_jig_type"],
      index
    ].compact

    # Use a hash of the components for consistency
    Digest::SHA256.hexdigest(id_components.join('|'))[0, 12]
  end

  # Generate a display name for a treatment
  def generate_display_name(treatment)
    process_name = treatment["type"].humanize.gsub('_', ' ').titleize
    target_thickness = treatment["target_thickness"]

    if target_thickness.present? && target_thickness > 0
      "#{process_name} #{target_thickness}μm"
    else
      process_name
    end
  end

  # Process and validate thickness value, rounding to 3 significant figures
  def process_thickness_value(value)
    return nil if value.blank?

    float_value = Float(value.to_s)
    return nil if float_value <= 0

    round_to_n_significant_figures(float_value, 3)
  end

  # Helper method to round to n significant figures
  def round_to_n_significant_figures(number, n)
    return 0.0 if number == 0
    magnitude = (Math.log10(number.abs)).floor
    factor = 10.0 ** (n - 1 - magnitude)
    (number * factor).round / factor
  end
end
