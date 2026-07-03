# app/models/customer_order.rb - Fixed outstanding logic and auto-marking
class CustomerOrder < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  belongs_to :contract_reviewed_by, class_name: 'User',
             foreign_key: :contract_reviewed_by_user_id,
             optional: true
  has_many :works_orders, dependent: :restrict_with_error
  has_many :release_notes, through: :works_orders

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

  # ---------------------------------------------------------------------------
  # Delivery / advice note consolidation
  #
  # A collection for an order can cover several release notes. Instead of making
  # the driver sign one advice note per release note, the advice note is printed
  # only on the "lead" release note (the lowest-numbered active one for the
  # order), and that single advice note summarises every release note on the
  # order. See app/views/release_notes/pdf.html.erb.
  # ---------------------------------------------------------------------------

  # Active (non-voided) release notes for this order, lowest number first.
  # Eager-loads works_order to avoid N+1 when building the advice-note summary.
  def delivery_release_notes
    release_notes.active.includes(:works_order).order(:number)
  end

  # The release note that carries the consolidated advice note.
  def lead_release_note
    delivery_release_notes.first
  end

  # ---------------------------------------------------------------------------
  # Order-complete notification (CustomerOrderMailer#order_ready)
  # ---------------------------------------------------------------------------

  # Every active works order fully released, and there's at least one.
  # Queried fresh (not from counter caches) so the trigger in
  # WorksOrder#update_is_fully_released_flag can't race the cache update.
  def fully_released?
    return false if voided?
    active_wos = works_orders.active
    active_wos.exists? && !active_wos.where(is_fully_released: false).exists?
  end

  # Does any active works order on this order carry a carriage/courier charge?
  # Decides "ready to collect" vs "dispatching by courier" in the
  # order-complete email. Non-carriage extras (rework etc.) don't count —
  # see AdditionalChargePreset#carriage?.
  def carriage_charge_present?
    charge_ids = works_orders.active
                             .flat_map { |wo| Array(wo.selected_charge_ids) }
                             .uniq
    return false if charge_ids.empty?

    AdditionalChargePreset.where(id: charge_ids).any?(&:carriage?)
  end

  # Release notes whose CofC PDFs get attached to the order-complete email:
  # active notes on active works orders (voided WOs can't have release notes
  # anyway — can_be_voided? requires none — but belt and braces).
  def email_release_notes
    release_notes.active
                 .joins(:works_order)
                 .where(works_orders: { voided: false })
                 .includes(works_order: :customer_order)
                 .order(:number)
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
