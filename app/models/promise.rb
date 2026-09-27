# app/models/promise.rb
#
# A promise: "we'll have <quantity> of WO<n> ready for <date>". Made on the
# phone by whoever answered it, kept by the section the work is homed to.
#
# Scope is a QUANTITY of a works order, not the works order: most promises
# are for a partial ("can we have 50 of the 200 by Thursday"). Promising a
# whole order is one promise per live works order (CustomerOrder#promise_all!).
#
# Whether a promise has been met is DERIVED, never stored: parts accepted on
# active release notes raised after the promise was made, counted against
# its quantity. Voiding a release note un-meets it automatically, and there
# is nothing to keep in sync. A promise the office withdraws is cancelled,
# not deleted, so the audit trail keeps what was said.
class Promise < ApplicationRecord
  belongs_to :works_order
  belongs_to :promised_by, class_name: "User", optional: true

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :due_on, presence: true
  validate  :quantity_within_unreleased, on: :create
  validate  :due_on_not_in_past, on: :create

  scope :active,    -> { where(cancelled_at: nil) }
  scope :cancelled, -> { where.not(cancelled_at: nil) }
  scope :by_due,    -> { order(:due_on, :created_at) }

  before_create -> { self.promised_by ||= Current.user }

  URGENT_WITHIN = 2 # working days

  def active?
    cancelled_at.nil?
  end

  def cancel!(user = nil)
    update!(cancelled_at: Time.current, cancelled_by_id: user&.id)
  end

  # Parts accepted on active release notes raised since the promise. Works
  # off the association so a preloaded works_order.release_notes costs no
  # query on the boards.
  def released_since
    works_order.release_notes.select { |rn| !rn.voided && rn.created_at >= created_at }
               .sum(&:quantity_accepted)
  end

  def outstanding
    [quantity - released_since, 0].max
  end

  def met?
    outstanding.zero?
  end

  def open?
    active? && !met?
  end

  # Signed working days to the due date; negative = late.
  def working_days_left
    WorkingDays.from_today(due_on)
  end

  def overdue?
    working_days_left.negative?
  end

  # :met / :overdue / :urgent / :ok - what colour the pill is.
  def status
    return :met if met?
    d = working_days_left
    return :overdue if d.negative?
    return :urgent  if d <= URGENT_WITHIN
    :ok
  end

  # "3 wd" / "today" / "2 wd late"
  def countdown_label
    d = working_days_left
    return "today" if d.zero?
    d.positive? ? "#{d} wd" : "#{-d} wd late"
  end

  def due_label
    due_on.strftime("%a %-d %b")
  end

  private

  def quantity_within_unreleased
    return if works_order.nil? || quantity.nil?
    max = works_order.unreleased_quantity
    return if quantity <= max
    errors.add(:quantity, "can't exceed the #{max} part(s) still to release on #{works_order.display_name}")
  end

  def due_on_not_in_past
    return if due_on.nil?
    errors.add(:due_on, "can't be in the past") if due_on < Date.current
  end
end
