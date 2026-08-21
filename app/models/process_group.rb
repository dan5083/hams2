# app/models/process_group.rb
#
# A process group is one physical tank load spanning several works orders
# whose parts run the IDENTICAL route - same operation text, same OCV specs
# (part number, description and customer spec may differ; the route may not).
# One sign-off session covers the whole bar.
#
# The group deliberately owns no process record of its own. The record lives
# on the LEAD works order's customised_process_data, running the existing
# engine unchanged - immutability guard, freeze semantics, discard rules,
# batches, forks, the lot. The group is membership + identity:
#
#   * process_fingerprint - hash of the route, stamped at creation; every
#     member must match it (Part#process_fingerprint). This is rule A made
#     structural: parts that don't hash identically cannot share a record.
#   * lead_works_order    - where the record lives. First member by WO number;
#     reassignable only while the record is unfrozen.
#
# Membership is fluid until the lead's record freezes (first sign-off /
# batch write). At freeze, the member manifest is embedded in the snapshot -
# the record itself states what was on the bar - and membership locks.
# Redo = discard on the lead, same rules as a solo WO but gated on EVERY
# member having no release notes.
class ProcessGroup < ApplicationRecord
  belongs_to :lead_works_order, class_name: 'WorksOrder', optional: true
  has_many :works_orders, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :process_fingerprint, presence: true

  before_validation :set_number, if: :new_record?
  # A group must never be leadless while it has members - the record lives on
  # the lead and every member page resolves through it. Belt (write): heal the
  # column on any save. Braces (read): lead_works_order below falls back to
  # the first member, so even a bad row renders instead of 500ing.
  before_save :ensure_lead
  before_destroy :guard_destroy

  # Read-side fallback for a leadless row. Deliberately does not write - a
  # GET must not mutate; the next save (or a console repair) fixes the column.
  def lead_works_order
    super || works_orders.order(:number).first
  end

  def display_name
    "PG#{number}"
  end

  def members
    works_orders.order(:number)
  end

  def total_quantity
    works_orders.where(voided: false).sum(:quantity)
  end

  def unreleased_quantity
    works_orders.where(voided: false).sum { |wo| wo.unreleased_quantity }
  end

  # The record is writable while any member still has work in the building.
  # An individual member closing itself (released and done) must not lock the
  # record for the rest of the bar.
  def record_open?
    works_orders.where(is_open: true, voided: false).exists?
  end

  def frozen?
    lead_works_order.present? && lead_works_order.frozen_operations.present?
  end

  # Embedded in the lead's snapshot at freeze - the audit answer to "one
  # signature, five part numbers": the record names every WO on the bar.
  def manifest
    members.map do |wo|
      {
        "wo" => wo.display_name,
        "part_number" => wo.part_number,
        "part_issue" => wo.part_issue,
        "part_description" => wo.part_description,
        "quantity" => wo.quantity,
        "customer_order" => wo.customer_order&.number
      }
    end
  end

  # --------------------------------------------------------------------------
  # Membership
  # --------------------------------------------------------------------------

  # Group at least two eligible works orders. All must be open, unreleased,
  # record-less, same customer, and hash to the same route.
  def self.create_for!(wos)
    wos = wos.to_a.uniq.sort_by { |w| w.number.to_i }
    raise "Pick at least two works orders to group" if wos.length < 2

    fingerprint = wos.first.part&.process_fingerprint
    raise "WO#{wos.first.number} has no operations to fingerprint" if fingerprint.blank?

    transaction do
      group = create!(process_fingerprint: fingerprint, lead_works_order: wos.first)
      wos.each { |wo| group.add_works_order!(wo) }
      group
    end
  end

  def add_works_order!(wo)
    raise "#{display_name} is frozen; membership is locked (discard the record on WO#{lead_works_order.number} first)" if frozen?
    assert_eligible!(wo)
    wo.update!(process_group: self)
    self.lead_works_order ||= wo
    save! if changed?
    wo
  end

  # Pre-freeze only: moving a WO out (to another bar, or back to solo) is the
  # "push parts over" path. If the lead leaves, the record moves with the
  # lead ROLE to the next member - safe, because pre-freeze the data is empty.
  def remove_works_order!(wo)
    raise "#{wo.display_name} is not in #{display_name}" unless wo.process_group_id == id
    raise "#{display_name} is frozen; its manifest names #{wo.display_name} and membership is locked" if frozen?

    transaction do
      wo.update!(process_group: nil)
      if lead_works_order_id == wo.id
        update!(lead_works_order: works_orders.order(:number).first)
      end
      destroy! if works_orders.count < 2
    end
    wo
  end

  # Move a WO between groups (or into a fresh one via create_for!).
  def transfer_works_order!(wo, to_group)
    remove_works_order!(wo)
    to_group.add_works_order!(wo)
  end

  private

  def assert_eligible!(wo)
    raise "#{wo.display_name} is voided" if wo.voided?
    raise "#{wo.display_name} is closed" unless wo.is_open
    raise "#{wo.display_name} already has release notes; it cannot join a group" if wo.release_notes.exists?
    if wo.process_group_id.present? && wo.process_group_id != id
      raise "#{wo.display_name} is already in #{wo.process_group.display_name}"
    end
    if wo.frozen_operations.present?
      raise "#{wo.display_name} already has its own frozen process record"
    end

    existing = works_orders.where.not(id: wo.id).first
    if existing && existing.customer_order.customer_id != wo.customer_order.customer_id
      raise "#{wo.display_name} is for a different customer"
    end

    fp = wo.part&.process_fingerprint
    raise "#{wo.display_name} has no operations to fingerprint" if fp.blank?
    if fp != process_fingerprint
      raise "#{wo.display_name} (#{wo.part_number}) does not run the identical route as this group - " \
            "diff its operations against #{lead_works_order&.part_number || 'the group'} before batching them together"
    end
  end

  def set_number
    return if number.present?
    sequence = Sequence.find_or_create_by(key: 'process_group_number')
    self.number = sequence.value
    sequence.increment!(:value)
  end

  def ensure_lead
    self.lead_works_order_id ||= works_orders.order(:number).pick(:id)
  end

  # A frozen group's record references this row (display_name in the
  # snapshot, lead resolution for members). Ungrouping is a pre-freeze
  # operation only; post-freeze the path back is discard on the lead.
  def guard_destroy
    return unless frozen?
    errors.add(:base, "#{display_name} is frozen; it cannot be deleted")
    throw :abort
  end
end
