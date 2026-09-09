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
# Membership is fluid until PROCESSING starts on the lead's record. The
# snapshot itself freezes at the first sign-off - and the first sign-off is
# contract review, done at booking, long before the bar is loaded - so a
# frozen snapshot is NOT the lock. Pulling a WO off the bar after review but
# before the first batch goes in the tank is routine ("push these over to
# Thursday's load"), and the route is identical by construction, so the
# review stands for whoever is left. The lock is the record showing the load
# has actually been processed (membership_locked?): any batch-scoped
# sign-off or OCV reading, or a batch date stamped.
#
# The member manifest is embedded in the lead's snapshot at freeze - the
# record itself states what was on the bar - and is refreshed on every
# post-freeze membership change, with a change log, so it never goes stale.
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
  # prepend: both must run BEFORE dependent: :nullify empties works_orders.
  # Declared in this order so guard_destroy runs first, then detach.
  before_destroy :detach_lead_record, prepend: true
  before_destroy :guard_destroy, prepend: true

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

  # The lead's snapshot exists (contract review or later). Informational -
  # it is NOT what locks membership; see membership_locked?.
  def frozen?
    lead_works_order.present? && lead_works_order.frozen_operations.present?
  end

  # Something has been recorded against a BATCH on the lead's record, so the
  # load has physically been through (or into) the process. From here the
  # manifest is evidence and membership is locked; the only way back is
  # discard on the lead.
  def membership_locked?
    lead_works_order.present? && lead_works_order.processing_started?
  end

  # Why `wo` cannot leave right now, or nil if it can. The view and the
  # mutators share this so the button and the raise never disagree.
  def removal_blocker(wo)
    return "#{wo.display_name} is not in #{display_name}" unless wo.process_group_id == id
    if membership_locked?
      return "#{display_name} has been processed; its record names #{wo.display_name} and membership is locked " \
             "(discard the record on WO#{lead_works_order.number} to change it)"
    end
    if lead_works_order_id == wo.id && frozen?
      return "#{wo.display_name} is the lead and holds the signed record (contract review); " \
             "remove the other members instead, or discard the record first"
    end
    nil
  end

  def can_remove?(wo)
    removal_blocker(wo).nil?
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
    if membership_locked?
      raise "#{display_name} has been processed; membership is locked (discard the record on WO#{lead_works_order.number} first)"
    end
    assert_eligible!(wo)
    transaction do
      wo.update!(process_group: self)
      self.lead_works_order ||= wo
      save! if changed?
      refresh_lead_manifest!("added", wo)
    end
    wo
  end

  # Moving a WO out (to another bar, or back to solo) is the "push parts
  # over" path. Allowed until processing starts. If the lead leaves pre-
  # freeze, the lead ROLE moves to the next member - safe, because the data
  # is empty. Post-freeze the lead holds the signed review and cannot leave
  # (removal_blocker); the others can, and the lead's manifest is rewritten
  # to say who is left. The leaver goes back to a blank solo record, so it
  # shows as pending contract review in its own right.
  def remove_works_order!(wo)
    if (why = removal_blocker(wo))
      raise why
    end

    transaction do
      wo.update!(process_group: nil)
      if lead_works_order_id == wo.id
        update!(lead_works_order: works_orders.order(:number).first)
      end
      if works_orders.count < 2
        destroy!
      else
        refresh_lead_manifest!("removed", wo)
      end
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

  # Post-freeze membership changes rewrite the manifest in the lead's
  # snapshot so the record always names exactly what is on the bar, and log
  # the change. The immutability guard only watches operations and batch
  # dates, so the "group" key is ours to maintain.
  def refresh_lead_manifest!(action, wo)
    lead = lead_works_order
    return unless lead&.operations_frozen?
    lead.reload
    data = (lead.customised_process_data || {}).deep_dup
    group = data["group"] || {}
    group["number"]  = display_name
    group["members"] = manifest
    group["changes"] = (group["changes"] || []) + [{
      "at" => Time.current.iso8601, "action" => action, "wo" => wo.display_name, "part_number" => wo.part_number
    }]
    data["group"] = group
    lead.update!(customised_process_data: data)
  end

  # The lead's record is a solo record again once the group goes: drop the
  # manifest so it doesn't claim a bar that no longer exists. Runs before
  # nullify (prepend), after guard_destroy.
  def detach_lead_record
    lead = lead_works_order
    return unless lead&.operations_frozen?
    data = (lead.customised_process_data || {}).deep_dup
    return unless data.key?("group")
    data["group"] = data["group"].merge(
      "dissolved_at" => Time.current.iso8601,
      "members" => []
    )
    lead.update!(customised_process_data: data)
  end

  # A processed group's record references this row (display_name in the
  # snapshot, lead resolution for members). Ungrouping is allowed until
  # processing starts; after that the path back is discard on the lead.
  def guard_destroy
    return unless membership_locked?
    errors.add(:base, "#{display_name} has been processed; it cannot be dissolved")
    throw :abort
  end
end
