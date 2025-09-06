# app/models/works_order.rb - Fixed pricing calculation and operations handling
class WorksOrder < ApplicationRecord
  belongs_to :customer_order
  belongs_to :part
  belongs_to :release_level
  belongs_to :transport_method
  belongs_to :issued_by, class_name: 'User', optional: true

  has_many :release_notes, dependent: :restrict_with_error
  has_one :customer, through: :customer_order

  store_accessor :additional_charge_data, :selected_charge_ids, :custom_amounts

  validates :number, presence: true, uniqueness: true
  validates :part_number, presence: true
  validates :part_issue, presence: true
  validates :part_description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :quantity_released, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :lot_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_type, inclusion: { in: ['lot', 'each'] }
  validates :each_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  validate :validate_quantity_released
  validate :validate_each_price_when_required
  validate :validate_part_matches

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :open, -> { where(is_open: true, voided: false) }
  scope :closed, -> { where(is_open: false, voided: false) }
  scope :with_unreleased_quantity, -> { where('quantity > quantity_released AND voided = false') }

  before_validation :calculate_lot_price_from_each_price, if: :should_calculate_lot_price?
  before_validation :set_part_details, if: :part_changed?
  before_validation :set_works_order_number, if: :new_record?
  after_initialize :set_defaults, if: :new_record?
  after_update :update_open_status


  def display_name
    "WO#{number}"
  end

  def customer_name
    customer_order.customer.name
  end

  def unreleased_quantity
    [quantity - quantity_released, 0].max
  end

  def quantity_remaining
    unreleased_quantity
  end

  def fully_released?
    quantity_released >= quantity
  end

  def manufacturing_complete?
    fully_released?
  end

  def can_be_released?
    !voided && !fully_released?
  end

  def can_be_voided?
    release_notes.empty?
  end

  def void!
    return false unless can_be_voided?
    update!(voided: true, is_open: false)
  end

  def total_lot_price
    lot_price
  end

  def total_each_price
    return 0 unless each_price.present? && price_type == 'each'
    quantity * each_price
  end

  def total_price
    case price_type
    when 'lot'
      total_lot_price
    when 'each'
      total_each_price
    else
      0
    end
  end

  def price_per_unit
    return lot_price / quantity if price_type == 'lot' && quantity > 0
    return each_price if price_type == 'each' && each_price.present?
    0
  end

  # FIXED: Get specification from part's specification field
  def specification
    part&.specification.presence || ""
  end

  def special_instructions
    part&.special_instructions
  end

  def process_type
    part&.process_type
  end

  def aerospace_defense?
    part&.aerospace_defense? || false
  end

  # FIXED: Get operations from part for route cards
  def operations_with_auto_ops
    return [] unless part

    part.get_operations_with_auto_ops
  rescue => e
    Rails.logger.error "Error getting operations for WO#{number}: #{e.message}"
    []
  end

  # For backwards compatibility - delegate to operations_with_auto_ops
  def operations_text
    operations_with_auto_ops.map.with_index(1) do |operation, index|
      "Operation #{index}: #{operation.operation_text}"
    end.join("\n\n")
  end

  def operations_summary
    ops = operations_with_auto_ops
    return "No operations configured" if ops.empty?
    ops.map(&:display_name).join(" → ")
  end

  # Treatment information for route cards
  def anodising_types
    part&.anodising_types || []
  end

  def target_thicknesses
    part&.target_thicknesses || []
  end

  def alloys
    part&.alloys || []
  end

  def anodic_classes
    part&.anodic_classes || []
  end

  # Release management
  def release_quantity(quantity_to_release, user:, remarks: nil)
    return false unless can_be_released?
    return false if quantity_to_release <= 0
    return false if quantity_to_release > unreleased_quantity

    ActiveRecord::Base.transaction do
      # Create release note
      release_note = release_notes.create!(
        number: next_release_note_number,
        issued_by: user,
        date: Date.current,
        quantity_accepted: quantity_to_release,
        quantity_rejected: 0,
        remarks: remarks
      )

      # Update quantity released
      new_quantity_released = quantity_released + quantity_to_release
      update!(quantity_released: new_quantity_released)

      release_note
    end
  end

  def reject_quantity(quantity_rejected, user:, remarks: nil)
    return false unless can_be_released?
    return false if quantity_rejected <= 0
    return false if quantity_rejected > unreleased_quantity

    ActiveRecord::Base.transaction do
      release_note = release_notes.create!(
        number: next_release_note_number,
        issued_by: user,
        date: Date.current,
        quantity_accepted: 0,
        quantity_rejected: quantity_rejected,
        remarks: remarks
      )

      # Update quantity released (rejected quantity still counts as "released")
      new_quantity_released = quantity_released + quantity_rejected
      update!(quantity_released: new_quantity_released)

      release_note
    end
  end

  def mixed_release(quantity_accepted, quantity_rejected, user:, remarks: nil)
    total_quantity = quantity_accepted + quantity_rejected
    return false unless can_be_released?
    return false if total_quantity <= 0
    return false if total_quantity > unreleased_quantity

    ActiveRecord::Base.transaction do
      release_note = release_notes.create!(
        number: next_release_note_number,
        issued_by: user,
        date: Date.current,
        quantity_accepted: quantity_accepted,
        quantity_rejected: quantity_rejected,
        remarks: remarks
      )

      # Update quantity released
      new_quantity_released = quantity_released + total_quantity
      update!(quantity_released: new_quantity_released)

      release_note
    end
  end

  # Calculate quantity released from release notes
  def calculate_quantity_released!
    total = release_notes.active.sum(:quantity_accepted) + release_notes.active.sum(:quantity_rejected)
    update_column(:quantity_released, total)
  end

  # Route card information for shop floor
  def route_card_data
    {
      works_order: self,
      part: part,
      customer: customer,
      operations: operations_with_auto_ops,
      specification: specification,
      special_instructions: special_instructions,
      aerospace_defense: aerospace_defense?,
      anodising_types: anodising_types,
      target_thicknesses: target_thicknesses,
      alloys: alloys
    }
  end

  # Status helpers
  def status
    return 'voided' if voided
    return 'closed' unless is_open
    return 'open' if can_be_released?
    'open'
  end

  def status_badge_class
    case status
    when 'voided'
      'bg-red-100 text-red-800'
    when 'closed'
      'bg-gray-100 text-gray-800'
    when 'open'
      'bg-green-100 text-green-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  # Search and filtering
  def self.search(term)
    return all if term.blank?

    term = term.strip.upcase
    where(
      "part_number ILIKE ? OR part_issue ILIKE ? OR part_description ILIKE ? OR CAST(number AS TEXT) ILIKE ?",
      "%#{term}%", "%#{term}%", "%#{term}%", "%#{term}%"
    )
  end

  def self.for_customer(customer)
    joins(:customer_order).where(customer_orders: { customer: customer })
  end

  def self.for_part(part)
    where(part: part)
  end

  def self.with_status(status)
    case status.to_s
    when 'open'
      open
    when 'closed'
      closed
    when 'voided'
      voided
    when 'active'
      active
    else
      all
    end
  end

  # Invoice and delivery information for release notes
  def invoice_customer_name
    customer_name
  end

  def invoice_address
    customer&.contact_address
  end

  def delivery_customer_name
    customer_name
  end

  def delivery_address
    customer&.contact_address
  end

  def get_selected_additional_charges
    return [] if selected_charge_ids.blank?
    AdditionalChargePreset.where(id: selected_charge_ids)
  end

  def get_custom_amount(charge_id)
    custom_amounts&.dig(charge_id.to_s)
  end

  # Add this method to the WorksOrder model (app/models/works_order.rb)

  # Get available additional charges for this works order
  def available_additional_charges
    AdditionalChargePreset.enabled.ordered
  end

  # Helper method to determine if this works order requires shipping
  def requires_shipping?
    !transport_method.name.downcase.include?('collect')
  end

  # Calculate total additional charges amount for a given set of charge IDs
  def calculate_additional_charges_total(charge_ids, custom_amounts = {})
    return 0.0 if charge_ids.blank?

    charges = AdditionalChargePreset.where(id: charge_ids)
    total = 0.0

    charges.each do |charge|
      if charge.is_variable?
        amount = custom_amounts[charge.id.to_s]&.to_f || charge.amount || 0.0
      else
        amount = charge.amount || 0.0
      end

      total += amount
    end

    total.round(2)
  end

  private

  def set_defaults
    self.is_open = true if is_open.nil?
    self.voided = false if voided.nil?
    self.quantity_released = 0 if quantity_released.nil?
    self.price_type = 'each' if price_type.blank? # Changed default to 'each'
    self.lot_price = 0.0 if lot_price.nil?
  end

  def set_works_order_number
    sequence = Sequence.find_or_create_by(key: 'works_order_number')
    self.number = sequence.value
    sequence.increment!(:value)
  end

  def set_part_details
    return unless part

    self.part_number = part.uniform_part_number
    self.part_issue = part.uniform_part_issue
    self.part_description = part.display_name if part_description.blank?
  end

  def validate_quantity_released
    return unless quantity && quantity_released

    if quantity_released > quantity
      errors.add(:quantity_released, "cannot exceed total quantity")
    end

    if quantity_released < 0
      errors.add(:quantity_released, "cannot be negative")
    end
  end

  def validate_each_price_when_required
    if price_type == 'each' && each_price.blank?
      errors.add(:each_price, "is required when price type is 'each'")
    end
  end

  def validate_part_matches
    return unless part && part_number && part_issue

    if part.uniform_part_number != part_number.upcase.gsub(/[^A-Z0-9]/, '')
      errors.add(:part, "number does not match selected part")
    end

    if part.uniform_part_issue != part_issue.upcase.gsub(/[^A-Z0-9]/, '')
      errors.add(:part, "issue does not match selected part")
    end
  end

  def part_changed?
    part_id_changed?
  end

  def update_open_status
    return if voided_changed? # Don't auto-update if manually voided

    # Close if fully released
    if fully_released? && is_open?
      update_column(:is_open, false)
    end
  end

  def next_release_note_number
    sequence = Sequence.find_or_create_by(key: 'release_note_number')
    number = sequence.value
    sequence.increment!(:value)
    number
  end

  # Pricing calculation logic
  def should_calculate_lot_price?
    price_type == 'each' && quantity.present? && each_price.present?
  end

  def calculate_lot_price_from_each_price
    Rails.logger.info "🔢 PRICING: Calculating lot_price from each_price (#{each_price}) × quantity (#{quantity})"
    calculated_price = (quantity * each_price).round(2)
    Rails.logger.info "🔢 PRICING: Calculated lot_price = #{calculated_price}"
    self.lot_price = calculated_price
  end
end
