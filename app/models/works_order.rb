# app/models/works_order.rb - Fixed pricing calculation and operations handling + counter cache updates
class WorksOrder < ApplicationRecord
  include CustomerOrderCounterCache

  # Upper bound on batches per works order. The practical driver is the process
  # record UI, which renders one batch at a time - this is a sanity ceiling on
  # derived batch counts (e.g. 1 part per batch on a 3,000 part order), not a
  # process limit.
  MAX_BATCHES = 120

  belongs_to :customer_order
  belongs_to :part
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
  validates :customer_reference, length: { maximum: 100 }, allow_blank: true

  validate :validate_quantity_released
  validate :validate_each_price_when_required

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :open, -> { where(is_open: true, voided: false) }
  scope :closed, -> { where(is_open: false, voided: false) }
  scope :with_unreleased_quantity, -> { where('quantity > quantity_released AND voided = false') }

  before_validation :calculate_lot_price_from_each_price, if: :should_calculate_lot_price?
  before_validation :set_part_details, if: :part_changed?
  before_validation :set_works_order_number, if: :new_record?
  before_validation :set_part_details_from_relationship, if: :should_sync_part_details?
  after_initialize :set_defaults, if: :new_record?
  after_update :update_open_status
  after_create :update_part_pricing, if: :should_update_part_pricing_on_create?
  after_update :update_part_pricing, if: :should_update_part_pricing?

  # NEW: Counter cache callbacks
  after_save :update_is_fully_released_flag
  after_save :update_customer_order_counts, if: :saved_change_to_quantity_released_or_voided_or_is_open?
  after_destroy :update_customer_order_counts

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

  def unvoid!
    return false unless voided
    update!(voided: false, is_open: true)
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

  def material
    part&.material.presence || ""
  end

  def specified_thicknesses
    part&.specified_thicknesses.presence || ""
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

  # ============================================================================
  # PAPERLESS PROCESS RECORD (frozen operations, batches, sign-offs, OCV)
  # ============================================================================
  #
  # The WO's process record lives in customised_process_data:
  #   "batch_count" - how many batches this WO runs (operator-set, default 1)
  #   "batches"     - [{"number" => 1, "date" => "2026-07-27"}] date set at
  #                   that batch's first sign-off
  #   "operations"  - frozen snapshot; per op:
  #       "sign_offs"    => { "1" => {"id","name"}, ... }  (keyed by batch)
  #       "ocv_readings" => { "1" => {field => value}, ... } (keyed by batch)
  #
  # Until the first write, operations render live from the part (pre-work
  # corrections flow through). The first write freezes the full snapshot -
  # verbatim text plus OCV specs - and everything happens against the frozen
  # copy from then on. The part can change; this WO's record cannot.

  def frozen_operations
    ops = customised_process_data&.dig("operations")
    ops.present? ? ops : nil
  end

  # Once an operation carries sign-offs, its text, OCV spec, existing
  # sign-offs, recorded readings, and batch dates are immutable through every
  # ActiveRecord path - console sessions and AI tooling included. New records
  # may be added via the mutators; history cannot be rewritten.
  before_save :protect_frozen_process_record, if: :customised_process_data_changed?

  # Discarding a process record is the digital equivalent of binning a route
  # card and reprinting it: allowed only while nothing has been released
  # against it, so nothing here has left the building. The superseded record
  # is NOT kept - pre-release it's a draft, not a record.
  #
  # What is kept is a one-line breadcrumb per discard. Not for auditors: for
  # you. A works order discarded once was a typo; discarded four times means
  # the part setup is wrong and every WO for it will do the same thing.
  # Sets the flag the immutability guard yields to; nothing else may.
  def discard_process_record!(user, reason = nil)
    raise "Nothing to discard - this works order has no frozen process record" unless operations_frozen?
    raise "This works order has release notes; its process record cannot be discarded" unless release_notes.empty?
    raise "This works order is closed" unless is_open

    data = customised_process_data || {}
    entry = { "at" => Time.current.iso8601, "by" => user.display_name }
    entry["reason"] = reason.to_s.strip if reason.present?

    # Batch structure is a property of THIS works order, not of the part, so it
    # survives - only the part-derived snapshot and everything recorded against
    # it goes. Batch dates were stamped at sign-off, so they go with it.
    self.customised_process_data = {
      "discards" => (data["discards"] || []) + [entry],
      "batch_count" => data["batch_count"],
      "parts_per_batch" => data["parts_per_batch"],
      "batches" => (data["batches"] || []).map { |b| b.slice("number", "qty") }
    }.compact

    @discarding_process_record = true
    save!
  ensure
    @discarding_process_record = false
  end

  def discards
    customised_process_data&.dig("discards") || []
  end

  def can_discard_process_record?
    operations_frozen? && is_open && release_notes.empty?
  end

  def protect_frozen_process_record
    return if @discarding_process_record

    old_ops = customised_process_data_was&.dig("operations")
    return if old_ops.blank?
    new_ops = customised_process_data&.dig("operations") || []

    old_ops.each do |old_op|
      pos = old_op["position"]
      signed = old_op["sign_offs"].presence || {}
      readings = old_op["ocv_readings"].presence || {}
      next if signed.empty? && readings.empty?

      new_op = new_ops.find { |o| o["position"] == pos }
      if new_op.nil?
        errors.add(:base, "Operation #{pos} has process records and cannot be removed")
        throw :abort
      end

      if signed.any? && (new_op["operation_text"] != old_op["operation_text"] || new_op["ocv"] != old_op["ocv"])
        errors.add(:base, "Operation #{pos} has signed batches; its text and OCV spec are immutable")
        throw :abort
      end

      signed.each do |batch, so|
        unless new_op.dig("sign_offs", batch) == so
          errors.add(:base, "Operation #{pos} batch #{batch}: sign-offs cannot be altered or removed")
          throw :abort
        end

        # A sign-off certifies the readings that were on screen when it was
        # made. Those readings are part of the record from that moment.
        old_row = readings[batch]
        next if old_row.blank?
        unless new_op.dig("ocv_readings", batch) == old_row
          errors.add(:base, "Operation #{pos} batch #{batch}: readings are locked by sign-off")
          throw :abort
        end
      end
    end

    # Batch numbers carrying any sign-off, across all operations.
    signed_batches = old_ops.flat_map { |o| (o["sign_offs"] || {}).keys }
                            .reject { |k| k == "wo" }.map(&:to_i).uniq

    (customised_process_data_was&.dig("batches") || []).each do |old_b|
      new_b = (customised_process_data&.dig("batches") || []).find { |b| b["number"] == old_b["number"] }

      if old_b["date"].present? && !(new_b && new_b["date"] == old_b["date"])
        errors.add(:base, "Batch #{old_b['number']} is dated; batch dates cannot be altered or removed")
        throw :abort
      end

      # Sign-off validates against the batch quantity, so re-batching must not
      # rewrite the quantity of a batch that has already been signed for.
      if signed_batches.include?(old_b["number"].to_i) && old_b["qty"].present? &&
         !(new_b && new_b["qty"] == old_b["qty"])
        errors.add(:base, "Batch #{old_b['number']} is signed off at qty #{old_b['qty']}; its quantity cannot be changed")
        throw :abort
      end
    end
  end

  def operations_frozen?
    frozen_operations.present?
  end

  # Pilot gate: the interactive process record is live for open WOs with
  # electroless nickel work only. Widen per process family as each area goes
  # paperless; delete once everything has.
  def paperless_record?
    return false unless is_open
    return true if operations_frozen?
    operations_with_auto_ops.any? { |op| op.process_type == 'electroless_nickel_plating' }
  end

  def process_batch_count
    (customised_process_data&.dig("batch_count") || 1).to_i.clamp(1, MAX_BATCHES)
  end

  # Set when the batch structure was derived from a parts-per-batch figure;
  # nil when the count was set by hand. Drives the redisplayed input only -
  # "batches" remains the record.
  def parts_per_batch
    customised_process_data&.dig("parts_per_batch")
  end

  # The normal way to batch a works order: state how many parts go through
  # together and let the count fall out. Batches 1..n-1 take the full load;
  # the last takes the remainder. 48 parts at 1 => 48 x 1. 100 at 30 =>
  # 3 x 30 + 1 x 10. Individual quantities stay editable afterwards for the
  # cases where physical reality diverges.
  def derive_batch_quantities(per_batch, total = quantity)
    per_batch = per_batch.to_i
    total = total.to_i
    return {} if per_batch < 1 || total < 1

    count = (total.to_f / per_batch).ceil
    (1..count).index_with { |n| n < count ? per_batch : total - (per_batch * (count - 1)) }
  end

  def set_parts_per_batch!(per_batch)
    per_batch = per_batch.to_i
    raise "Parts per batch must be at least 1" if per_batch < 1
    raise "Parts per batch cannot exceed the order quantity (#{quantity})" if per_batch > quantity.to_i

    derived = derive_batch_quantities(per_batch)
    count = derived.length
    if count > MAX_BATCHES
      raise "#{per_batch} per batch on #{quantity} parts gives #{count} batches (max #{MAX_BATCHES})"
    end

    highest_used = highest_recorded_batch
    raise "Batch #{highest_used} already has records; cannot reduce to #{count} batches" if count < highest_used

    # Refuse rather than reconcile: a signed batch's quantity is part of what
    # the sign-off certified.
    clashes = signed_batch_numbers.select { |n| derived[n].to_s != process_batch_qty(n).to_s }
    if clashes.any?
      raise "Batch #{clashes.join(', ')} already signed off at a different quantity; " \
            "re-batching would rewrite the record"
    end

    freeze_operations!
    batches = customised_process_data["batches"] ||= []
    derived.each do |n, qty|
      entry = batches.find { |b| b["number"] == n } || (batches << { "number" => n }).last
      entry["qty"] = qty.to_s
    end
    batches.reject! { |b| b["number"].to_i > count }
    customised_process_data["batch_count"] = count
    customised_process_data["parts_per_batch"] = per_batch
    customised_process_data_will_change!
    save!
  end

  # Batch numbers carrying a sign-off on any operation.
  def signed_batch_numbers
    (frozen_operations || []).flat_map { |o| (o["sign_offs"] || {}).keys }
                             .reject { |k| k == "wo" }.map(&:to_i).uniq.sort
  end

  # :complete when every batch-scoped operation is signed for that batch,
  # :in_progress once anything is recorded against it, :not_started otherwise.
  def batch_statuses
    ops = operations_for_display.reject { |o| wo_scoped_operation?(o) }
    (1..process_batch_count).index_with do |n|
      key = n.to_s
      signed = ops.count { |o| (o["sign_offs"] || {})[key].present? }
      if ops.any? && signed == ops.length
        :complete
      elsif signed > 0 || ops.any? { |o| (o["ocv_readings"] || {})[key].present? }
        :in_progress
      else
        :not_started
      end
    end
  end

  # Lowest batch that still has work outstanding - the sensible landing batch
  # when the page is opened without an explicit one.
  def first_incomplete_batch
    batch_statuses.find { |_n, status| status != :complete }&.first || process_batch_count
  end

  # Next operation in THIS batch still needing a sign-off, searching forward
  # from `after` and wrapping. nil when the batch has no outstanding work.
  # WO-scoped operations are skipped - they certify the order, not a batch.
  def next_unsigned_operation_in(batch, after: 0)
    key = batch.to_i.to_s
    positions = operations_for_display
                  .reject { |o| wo_scoped_operation?(o) }
                  .select { |o| (o["sign_offs"] || {})[key].blank? }
                  .map { |o| o["position"].to_i }
                  .sort

    positions.find { |p| p > after.to_i } || positions.first
  end

  def signed_count_for(op)
    keys = sign_off_keys_for(op)
    (op["sign_offs"] || {}).count { |k, v| keys.include?(k) && v.present? }
  end

  def process_batches
    customised_process_data&.dig("batches") || []
  end

  def process_batch_date(batch_number)
    process_batches.find { |b| b["number"] == batch_number.to_i }&.dig("date")
  end

  def process_batch_qty(batch_number)
    process_batches.find { |b| b["number"] == batch_number.to_i }&.dig("qty")
  end

  # qtys: { "1" => "20", "2" => "13" } - parts per batch, recorded like the
  # route card's Qty column. Editable; the sign-offs are the immutable record.
  def set_batch_count!(count, qtys = {})
    count = count.to_i
    raise "Batch count must be between 1 and #{MAX_BATCHES}" unless (1..MAX_BATCHES).cover?(count)

    highest_used = highest_recorded_batch
    raise "Batch #{highest_used} already has records; cannot reduce below it" if count < highest_used

    freeze_operations!
    customised_process_data["batch_count"] = count
    # A hand-set count no longer follows from a parts-per-batch figure.
    customised_process_data.delete("parts_per_batch")
    batches = customised_process_data["batches"] ||= []
    (qtys || {}).each do |number, qty|
      n = number.to_i
      next unless (1..count).cover?(n)
      entry = batches.find { |b| b["number"] == n } || (batches << { "number" => n }).last
      qty.to_s.strip.empty? ? entry.delete("qty") : entry["qty"] = qty.to_s.strip
    end
    customised_process_data_will_change!
    save!
  end

  # Correct one batch's quantity without disturbing the rest of the structure -
  # short loads, scrapped parts, a batch split across two racks.
  def set_batch_qty!(batch_number, qty)
    n = normalise_batch!(batch_number)
    raise "Batch #{n} is signed off; its quantity cannot be changed" if signed_batch_numbers.include?(n)

    freeze_operations!
    batches = customised_process_data["batches"] ||= []
    entry = batches.find { |b| b["number"] == n } || (batches << { "number" => n }).last
    qty.to_s.strip.empty? ? entry.delete("qty") : entry["qty"] = qty.to_s.strip
    customised_process_data_will_change!
    save!
  end

  # Sum of recorded batch quantities. Compared against `quantity` on screen as
  # a display-only check - a typo in one of 120 boxes is otherwise invisible.
  def batched_quantity_total
    (1..process_batch_count).sum { |n| process_batch_qty(n).to_i }
  end

  # Uniform hash shape for the show page, frozen or live.
  def operations_for_display
    frozen_operations || operations_with_auto_ops.map.with_index(1) do |op, i|
      operation_snapshot(op, i)
    end
  end

  def freeze_operations!
    return frozen_operations if operations_frozen?

    ops = operations_with_auto_ops.map.with_index(1) { |op, i| operation_snapshot(op, i) }
    raise "Cannot freeze: no operations available for WO#{number}" if ops.empty?
    # Checklist items are NOT embedded: the marker resolves to the current form
    # issue at render time, keeping reviews correctable and current. The issue
    # answered against is recorded with the responses; git history holds what
    # each issue said.

    data = customised_process_data || {}
    self.customised_process_data = data.merge(
      "operations" => ops,
      "batch_count" => (data["batch_count"] || 1),
      "batches" => (data["batches"] || [])
    )
    save!
    frozen_operations
  end

  # Each operation has a batch DOMAIN: today either the whole works order
  # (contract review and incoming inspection precede batching) or every batch
  # (default).
  # EXTENSION POINT: when treatment cycles gain their own batch structures
  # (different part/batch qtys per cycle), this method becomes the mapping
  # from an operation to its set of sign-off keys - nothing else changes.
  def sign_off_keys_for(op)
    wo_scoped_operation?(op) ? ["wo"] : (1..process_batch_count).map(&:to_s)
  end

  # Operations whose sign-off certifies the works order rather than a batch.
  # Contract review happens at booking; incoming inspection counts and examines
  # the delivery as it arrives. Both land before the work is split into batches,
  # so neither has a batch to be signed against.
  WO_SCOPED_OPERATION_IDS = %w[CONTRACT_REVIEW INCOMING_INSPECT].freeze

  def wo_scoped_operation?(op)
    op["process_type"] == "contract_review" ||
      WO_SCOPED_OPERATION_IDS.include?(op["id"])
  end

  def sign_off_operation!(position, batch_number, user)
    freeze_operations!
    op = find_frozen_operation!(position)
    op["sign_offs"] ||= {}

    wo_scoped = wo_scoped_operation?(op)
    key = wo_scoped ? "wo" : normalise_batch!(batch_number).to_s
    label = wo_scoped ? "" : " batch #{key}"
    raise "Operation #{position}#{label} already signed off" if op["sign_offs"][key].present?

    # A sign-off certifies a complete record. Batch-scoped ops need the batch
    # quantity set; WO-scoped ops (contract review, incoming inspection) don't -
    # batches may not physically exist yet.
    if !wo_scoped && process_batch_qty(key).blank?
      raise "Enter a quantity for batch #{key} (top of the operations list) before signing off"
    end
    if op["ocv"].present?
      row = op.dig("ocv_readings", key) || {}
      missing = (op["ocv"]["fields"] || []).map(&:to_s).select { |f| row[f].to_s.strip.empty? }
      if missing.any?
        raise "Record #{missing.map(&:humanize).join(', ')}#{wo_scoped ? '' : " for batch #{key}"} before signing off operation #{position}"
      end

      items = OperationLibrary::ContractReviewOperations.resolve_checklist(op["ocv"]["checklist"])
      if items.any?
        answered = op["checklist_responses"] || {}
        unanswered = items.reject { |i| answered.dig(i["id"], "answer").present? }
        if unanswered.any?
          raise "Answer all checklist items before signing off contract review (#{unanswered.length} remaining)"
        end
      end
    end

    op["sign_offs"][key] = { "id" => user.id, "name" => user.display_name }
    stamp_batch_date(key.to_i) unless wo_scoped
    customised_process_data_will_change!
    save!
    remember_part_checklist_answers(op)
  end

  # responses: { item_id => {"answer" => "YES"/"NO", "comment" => "..."} }.
  # Sliced against the op's checklist item ids; blank answers dropped.
  def save_checklist_responses!(position, responses, user)
    freeze_operations!
    op = find_frozen_operation!(position)
    items = OperationLibrary::ContractReviewOperations.resolve_checklist(op.dig("ocv", "checklist"))
    raise "Operation #{position} has no checklist" if items.blank?

    ids = items.map { |i| i["id"] }
    cleaned = {}
    (responses || {}).each do |item_id, r|
      next unless ids.include?(item_id.to_s)
      answer = r["answer"].to_s.strip.upcase
      next unless %w[YES NO].include?(answer)
      cleaned[item_id.to_s] = { "answer" => answer, "comment" => r["comment"].to_s.strip }
    end

    op["checklist_responses"] = cleaned
    op["checklist_issue"] = OperationLibrary::ContractReviewOperations::ISSUE
    op["checklist_completed_by"] = { "id" => user.id, "name" => user.display_name }
    customised_process_data_will_change!
    save!
  end

  # Checklist values for display: explicit responses on this WO, falling back
  # to the part's remembered answers for part-scoped items.
  def checklist_prefill(op)
    responses = op["checklist_responses"] || {}
    memory = part&.customisation_data&.dig("contract_review_memory") || {}
    OperationLibrary::ContractReviewOperations.resolve_checklist(op.dig("ocv", "checklist")).each_with_object({}) do |item, out|
      id = item["id"]
      if responses[id].present?
        out[id] = responses[id].merge("from_memory" => false)
      elsif item["scope"] == "part" && memory[id].present?
        out[id] = { "answer" => memory[id]["answer"], "comment" => memory[id]["comment"], "from_memory" => true }
      end
    end
  end

  # readings: { "1" => {field => value}, "2" => ... } keyed by batch number.
  # Values are sliced against the op's OCV spec fields; fully blank rows dropped.
  def save_ocv_readings!(position, readings, user)
    freeze_operations!
    op = find_frozen_operation!(position)
    spec = op["ocv"]
    raise "Operation #{position} has no OCV spec" if spec.blank?

    allowed = (spec["fields"] || []).map(&:to_s)
    valid_keys = sign_off_keys_for(op)
    cleaned = {}
    (readings || {}).each do |batch_key, row|
      next unless valid_keys.include?(batch_key.to_s)
      values = row.to_h.slice(*allowed).transform_values { |v| v.to_s.strip }
      cleaned[batch_key.to_s] = values unless values.values.all?(&:blank?)
    end

    # MERGE, never replace. The page posts only the batch being worked on, so
    # a wholesale assignment would delete every batch absent from the form.
    existing = op["ocv_readings"] || {}
    locked = (op["sign_offs"] || {}).keys.select { |k| cleaned.key?(k) && cleaned[k] != existing[k] }
    if locked.any?
      raise "Batch #{locked.join(', ')} is signed off; its readings cannot be changed"
    end

    op["ocv_readings"] = existing.merge(cleaned)
    op["ocv_recorded_by"] = { "id" => user.id, "name" => user.display_name }
    customised_process_data_will_change!
    save!
  end

  def find_frozen_operation!(position)
    op = frozen_operations&.find { |o| o["position"] == position.to_i }
    raise "No operation at position #{position} on WO#{number}" unless op
    op
  end

  private

  def operation_snapshot(op, position)
    ocv = op.try(:ocv)
    {
      "position" => position,
      "id" => op.id,
      "display_name" => (op.respond_to?(:display_name) ? op.display_name : op.id),
      "operation_text" => op.operation_text,
      "process_type" => (op.respond_to?(:process_type) ? op.process_type : nil),
      "target_thickness" => (op.respond_to?(:target_thickness) ? op.target_thickness : nil),
      "ocv" => (ocv.respond_to?(:deep_stringify_keys) ? ocv.deep_stringify_keys : ocv),
      "sign_offs" => {},
      "ocv_readings" => {}
    }
  end

  def normalise_batch!(batch_number)
    n = batch_number.to_i
    raise "Batch #{batch_number} is outside this WO's batch count (#{process_batch_count})" unless (1..process_batch_count).cover?(n)
    n
  end

  # Highest batch number carrying any record (sign-off, reading, or date) -
  # batch count cannot be reduced below this.
  def highest_recorded_batch
    ops = frozen_operations || []
    numbers = ops.flat_map { |o| (o["sign_offs"] || {}).keys + (o["ocv_readings"] || {}).keys }.map(&:to_i)
    # Only DATED batches count as records. A batch that merely has a planned
    # quantity carries nothing, and treating it as a record would make any
    # re-batching downward impossible after the first structure was set.
    numbers += process_batches.select { |b| b["date"].present? }.map { |b| b["number"].to_i }
    numbers.max || 0
  end

  # On signing off a checklist op, part-scoped answers are remembered on the
  # part and pre-filled on future WOs. Convenience, not record: failure here
  # never unwinds the sign-off.
  def remember_part_checklist_answers(op)
    items = OperationLibrary::ContractReviewOperations.resolve_checklist(op.dig("ocv", "checklist"))
    responses = op["checklist_responses"] || {}
    return if items.empty? || responses.empty? || part.nil?

    part_ids = items.select { |i| i["scope"] == "part" }.map { |i| i["id"] }
    to_remember = responses.slice(*part_ids)
    return if to_remember.empty?

    data = part.customisation_data || {}
    memory = data["contract_review_memory"] || {}
    to_remember.each do |id, r|
      memory[id] = { "answer" => r["answer"], "comment" => r["comment"], "source_wo" => number, "on" => Date.current.iso8601 }
    end
    part.update!(customisation_data: data.merge("contract_review_memory" => memory))
  rescue => e
    Rails.logger.error "Part checklist memory writeback failed for WO#{number}: #{e.message}"
  end

  def stamp_batch_date(batch_number)
    batches = customised_process_data["batches"] ||= []
    entry = batches.find { |b| b["number"] == batch_number } || (batches << { "number" => batch_number }).last
    entry["date"] ||= Date.current.iso8601
  end

  public


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

    # IMPORTANT: Manually trigger flag update since update_column bypasses callbacks
    update_is_fully_released_flag
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

  # Parsed components of the customer's own reference string (Lufthansa-style),
  # e.g. "CS-Order: 4711 / S/N: AB123". Single source for the regexes used on
  # the CofC PDF (release_notes/pdf) and in customer emails — if the format
  # ever changes, change it here only.
  #   cs_order  -> shown alongside our customer order number
  #   serial_no -> shown alongside our part number
  def parsed_customer_reference
    ref = customer_reference
    return { cs_order: nil, serial_no: nil } if ref.blank?

    {
      cs_order:  ref.match(/CS-?Order[:\s]+([^\s\/]+)/i)&.captures&.first,
      serial_no: ref.match(/(?:S\/N|SerialNo\.)[:\s]+(.+)/i)&.captures&.first&.strip
    }
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

  # Get available additional charges for this works order
  def available_additional_charges
    AdditionalChargePreset.enabled.ordered
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

  def has_quality_issues?
    release_notes.joins(:external_ncrs).exists?
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

    self.part_number = part.part_number
    self.part_issue = part.part_issue
    self.part_description = "#{part.part_number}-#{part.part_issue}" if part_description.blank?
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

  def should_update_part_pricing?
    price_type == 'each' && each_price_changed? && each_price.present? && each_price > 0
  end

  def update_part_pricing
    part.update!(each_price: each_price)
  end

  def should_update_part_pricing_on_create?
    price_type == 'each' && each_price.present? && each_price > 0
  end

  def should_sync_part_details?
    part_id_changed? ||
    part_number.blank? ||
    part_issue.blank? ||
    (part && part.part_number != part_number) ||
    (part && part.part_issue != part_issue)
  end

  def set_part_details_from_relationship
    return unless part

    self.part_number = part.part_number
    self.part_issue = part.part_issue
    self.part_description = part.description.presence || "#{part.part_number}-#{part.part_issue}"
  end

  # NEW: Counter cache update methods
  def update_is_fully_released_flag
    new_value = quantity_released >= quantity && !voided
    if is_fully_released != new_value
      update_column(:is_fully_released, new_value)
      # Trigger customer order count update if this changed
      update_customer_order_counts if saved_changes?
      # This WO just became fully released — if it was the last one on the
      # order, tell the buyer the order is ready. Deliberately NOT behind
      # saved_changes? so the release-note path (calculate_quantity_released!
      # -> update_column -> here) also fires.
      notify_buyer_if_order_complete if new_value
    end
  end

  # Send the order-complete email when the whole customer order has just
  # become fully released. CustomerOrder#fully_released? re-queries the WO
  # flags directly, so this doesn't depend on counter caches being current.
  # PDF generation happens inside the mailer, so deliver_later keeps Grover
  # off the request path regardless of queue adapter.
  def notify_buyer_if_order_complete
    co = customer_order
    return unless co&.fully_released?

    CustomerOrderMailer.order_ready(co).deliver_later
  rescue StandardError => e
    # Never let a notification failure break a release.
    Rails.logger.error "Order-complete email enqueue failed for CO #{co&.id}: #{e.message}"
  end

  def saved_change_to_quantity_released_or_voided_or_is_open?
    saved_change_to_quantity_released? || saved_change_to_voided? || saved_change_to_is_open?
  end
end
