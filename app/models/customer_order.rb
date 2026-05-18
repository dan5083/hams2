# app/models/customer_order.rb - Fixed outstanding logic and auto-marking
class CustomerOrder < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  belongs_to :contract_reviewed_by, class_name: 'User',
             foreign_key: :contract_reviewed_by_user_id,
             optional: true
  has_many :works_orders, dependent: :restrict_with_error

  validates :number, presence: true
  validates :number, uniqueness: { scope: :customer_id }
  validates :date_received, presence: true

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(date_received: :desc) }

  # FIXED: Outstanding logic - check for open works orders, not just any works orders
  scope :outstanding, -> {
    where(voided: false).where(
      'NOT EXISTS (SELECT 1 FROM works_orders WHERE works_orders.customer_order_id = customer_orders.id) OR ' +
      'EXISTS (SELECT 1 FROM works_orders WHERE works_orders.customer_order_id = customer_orders.id AND works_orders.voided = false AND works_orders.is_open = true)'
    )
  }

  after_initialize :set_defaults, if: :new_record?
  after_create :mark_customer_as_customer

  def display_name
    "#{customer.name} - #{number}"
  end

  def invoice_customer_name
    customer.name
  end

  def invoice_address
    customer.contact_address
  end

  def delivery_customer_name
    customer.name
  end

  def delivery_address
    customer.contact_address
  end

  def void!
    transaction do
      if has_non_voided_works_orders?
        raise StandardError, "Cannot void customer order until every works order has been voided"
      end
      update!(voided: true)
    end
  end

  def can_be_voided?
    !has_non_voided_works_orders?
  end

  def has_non_voided_works_orders?
    works_orders.active.exists?
  end

  def total_value
    works_orders.active.sum(:lot_price)
  end

  def total_quantity
    works_orders.active.sum(:quantity)
  end

  # FIXED: Outstanding logic - should check for open works orders
  def outstanding?
    return false if voided?
    works_orders.empty? || works_orders.where(voided: false, is_open: true).exists?
  end

  def can_be_deleted?
    works_orders.empty?
  end

  # Contract review
  def contract_reviewed?
    contract_reviewed_by_user_id.present?
  end

  def mark_contract_reviewed!(user)
    update!(contract_reviewed_by_user_id: user.id)
  end

  def unmark_contract_reviewed!
    update!(contract_reviewed_by_user_id: nil)
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.date_received = Date.current if date_received.blank?
  end

  def mark_customer_as_customer
    unless customer.is_customer?
      customer.update!(is_customer: true)
      Rails.logger.info "Auto-marked #{customer.name} as customer due to new customer order #{number}"
    end
  end
end
