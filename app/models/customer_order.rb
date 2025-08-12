class CustomerOrder < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  has_many :works_orders, dependent: :restrict_with_error

  validates :number, presence: true
  validates :number, uniqueness: { scope: :customer_id }
  validates :date_received, presence: true

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :for_customer, ->(customer) { where(customer: customer) }
  scope :recent, -> { order(date_received: :desc) }
  scope :outstanding, -> {
    left_joins(:works_orders)
      .where(voided: false)
      .where(
        works_orders: { id: nil }
      ).or(
        where(voided: false)
          .joins(:works_orders)
          .where(works_orders: { voided: false })
      ).distinct
  }

  after_initialize :set_defaults, if: :new_record?

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

  def outstanding?
    !voided && (works_orders.empty? || works_orders.active.exists?)
  end

  def can_be_deleted?
    works_orders.empty?
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.date_received = Date.current if date_received.blank?
  end
end
