# app/services/shop_section_board.rb
#
# Shop-floor section boards, derived ENTIRELY from data that already exists:
# each works order's operations_for_display (the frozen snapshot once the
# record has started, the live part route before that) plus the part's
# treatment selections. No migrations, no new columns, no writes.
#
# Sign-offs drive status. "Jigged ready for anodise" means: the jig op
# feeding an anodising op is signed for a batch and the anodising op is not.
# An unfrozen record has no sign-offs, so it can't be "jigged" - it shows on
# the JIGGERS board (work awaiting jigging) instead. That split falls out of
# the record naturally.
class ShopSectionBoard
  # ==========================================================================
  # ⚠️ CONFIG - the only thing that should ever need editing.
  #
  # Which vats live where. An op is assigned to a shop by the vat number(s)
  # in its text; a jig op belongs to the shop of the next vat-bearing op
  # after it. GUESSED from the operation library (hard anodising runs vats
  # 1,2,3,5,9,12; standard runs vat 6; ENP runs 7,8) - fix the lists, the
  # boards follow.
  # ==========================================================================
  SHOP_VATS = {
    "shop1"    => [1, 2, 3],
    "shop2"    => [5, 6],
    "factory2" => [9, 12],
  }.freeze

  SECTIONS = {
    "enp"             => "ENP",
    "shop1_anodisers" => "Shop 1 · Anodisers",
    "shop2_anodisers" => "Shop 2 · Anodisers",
    "shop1_jiggers"   => "Shop 1 · Jiggers",
    "shop2_jiggers"   => "Shop 2 · Jiggers",
    "factory2"        => "Factory 2",
    "contract_review" => "Contract Review",
  }.freeze

  # Navbar badge cache. Busted by WorksOrder's after_commit; the TTL is only
  # a backstop against a missed invalidation.
  CONTRACT_REVIEW_COUNT_CACHE_KEY = "sections/contract_review_pending_count".freeze

  ANODISING_TYPES = %w[standard_anodising hard_anodising chromic_anodising].freeze
  ENP_VATS = [7, 8].freeze

  ENP_TYPE_LABELS = {
    "high_phosphorous" => "High Phos — Vandalloy 4100",
    "medium_phosphorous" => "Medium Phos — Nicklad 767",
    "low_phosphorous" => "Low Phos — Nicklad ELV 824",
    "ptfe_composite" => "PTFE — Nicklad Ice",
    "unknown" => "Other / unclassified",
  }.freeze

  ENP_TYPE_ORDER = ENP_TYPE_LABELS.keys.freeze

  def initialize(works_orders)
    @jobs = works_orders.map { |wo| Job.new(wo) }
  end

  # -- ENP board -------------------------------------------------------------
  # { enp_type => { label:, jobs: [..thickness asc..], by_pretreat: { alloy_label => [jobs] } } }
  def enp_groups
    enp_jobs = @jobs.select(&:enp?)
    ENP_TYPE_ORDER.filter_map do |type|
      jobs = enp_jobs.select { |j| j.enp_type == type }.sort_by { |j| [j.enp_thickness || Float::INFINITY, j.number] }
      next if jobs.empty?
      {
        type: type,
        label: ENP_TYPE_LABELS[type],
        jobs: jobs,
        by_pretreat: jobs.group_by(&:enp_pretreat_label).sort.to_h,
      }
    end
  end

  # -- Contract Review board -------------------------------------------------
  # PAPERLESS live work that has never been released and whose contract
  # review is not yet signed. The paperless gate matters: pre-pilot /
  # non-paperless WOs complete on their printed route card and never carry a
  # digital review sign-off, so without it every paper job counts as
  # "unreviewed" forever. WorksOrder.paperless_ids is the memoised
  # collection form of paperless_record? (one Part#paperless? per unique
  # part, not per row).
  #
  # The review is signed once, on the record owner (a group lead answers for
  # all its members), so the queue is one row per RECORD - paperless_ids
  # already drops grouped members (their record IS the lead's), and the
  # group_by mops up any residual duplication. Unfrozen records have no
  # sign-offs at all, so brand-new work lands here automatically - this
  # board is the entry gate the jiggers boards (which require
  # contract_reviewed?) deliberately exclude.
  def contract_review_queue
    paperless = WorksOrder.paperless_ids(@jobs.map(&:wo))
    pending = @jobs.select { |j| paperless.include?(j.wo.id) && j.awaiting_contract_review? }
    pending.group_by { |j| j.wo.process_record_owner.id }
           .map { |owner_id, js| js.find { |j| j.wo.id == owner_id } || js.first }
           .sort_by(&:number)
  end

  # For the navbar badge. The cache is load-bearing here: paperless_ids runs
  # Part#paperless? per unique live part (route generation), so this must
  # only recompute on bust - see WorksOrder's after_commit
  # :expire_contract_review_count.
  def self.pending_contract_review_count
    Rails.cache.fetch(CONTRACT_REVIEW_COUNT_CACHE_KEY, expires_in: 1.hour) do
      scope = WorksOrder.open
                        .with_unreleased_quantity
                        .includes(:release_notes, :process_group, :part)
      new(scope).contract_review_queue.size
    end
  end

  # -- Anodisers boards ------------------------------------------------------
  # Jigged, awaiting anodise in this shop's vats. One row per ready
  # (anodising op, batches) pair - a two-treatment WO can appear twice.
  def anodise_ready(shop)
    vats = SHOP_VATS.fetch(shop)
    @jobs.flat_map { |j| j.anodise_ready_rows(vats) }
         .sort_by { |r| [r[:vats].min || 99, r[:job].number] }
  end

  # -- Jiggers boards --------------------------------------------------------
  # Work whose next jig (for this shop's processes) hasn't been signed yet.
  def jigging_queue(shop)
    vats = SHOP_VATS.fetch(shop)
    @jobs.flat_map { |j| j.jig_queue_rows(vats) }
         .sort_by { |r| r[:job].number }
  end

  # ==========================================================================
  # One works order, with everything the boards need parsed out of its ops.
  # Grouped members defer to the lead's record for sign-offs (the record IS
  # the lead's) but keep their own identity for display.
  # ==========================================================================
  class Job
    attr_reader :wo

    delegate :number, :display_name, :part_number, :quantity, :customer_name, to: :wo

    def initialize(wo)
      @wo = wo
    end

    def ops
      @ops ||= @wo.process_record_owner.operations_for_display || []
    rescue => e
      Rails.logger.error "SectionBoard: ops failed for WO#{@wo.number}: #{e.message}"
      []
    end

    def frozen?
      @wo.process_record_owner.operations_frozen?
    end

    # ---- Op classification -------------------------------------------------
    # Copied routes (ENP part copying / copy_operations) carry their real ops
    # as COPIED_OP_N with process_type "manual", so process_type alone is
    # blind to them. Classify by process_type first, then fall back to the
    # op text for manual ops.

    def anodising_op?(op)
      return true if ANODISING_TYPES.include?(op["process_type"])
      op["process_type"] == "manual" && op["operation_text"].to_s.match?(/\b(hard|standard|chromic)\s+anodis/i)
    end

    def enp_op?(op)
      return true if op["process_type"] == "electroless_nickel_plating"
      op["process_type"] == "manual" && op["operation_text"].to_s.match?(/electroless\s+nickel/i)
    end

    def jig_op?(op)
      return true if op["process_type"] == "jig"
      op["process_type"] == "manual" && op["operation_text"].to_s.match?(/\A[\s*]*jig\b/i)
    end

    def sealing_op?(op)
      return true if %w[sealing dichromate_sealing].include?(op["process_type"])
      op["process_type"] == "manual" && op["operation_text"].to_s.match?(/\A[\s*]*(dichromate\s+)?seal\b/i)
    end

    def dye_op?(op)
      return true if op["process_type"] == "dye"
      op["process_type"] == "manual" && op["operation_text"].to_s.match?(/\A[\s*]*\w+\s+dye\b/i)
    end

    # ---- ENP ---------------------------------------------------------------

    def enp_op
      @enp_op ||= ops.find { |o| enp_op?(o) }
    end

    def enp?
      enp_op.present?
    end

    # From the op id (survives freezing); text as fallback.
    def enp_type
      id = enp_op&.dig("id").to_s
      text = enp_op&.dig("operation_text").to_s
      return "high_phosphorous"   if id.start_with?("HIGH_PHOS")   || text.include?("High Phos")
      return "medium_phosphorous" if id.start_with?("MEDIUM_PHOS") || text.include?("Medium Phos")
      return "low_phosphorous"    if id.start_with?("LOW_PHOS")    || text.include?("Low Phos")
      return "ptfe_composite"     if id.start_with?("PTFE")        || text.include?("PTFE")
      "unknown"
    end

    # "Time for 25μm" interpolated into the frozen text; part fallback.
    def enp_thickness
      t = enp_op&.dig("operation_text").to_s[/Time for (\d+(?:\.\d+)?)\s*μm/, 1]
      return t.to_f if t
      @wo.part&.target_thicknesses&.map(&:to_f)&.max
    end

    # The pretreatment line is a function of the selected alloy, so the alloy
    # names the pre-process. Read from the part's ENP treatment selection.
    def enp_pretreat_label
      data = @wo.part&.get_treatments&.find { |t| t[:operation].process_type == "electroless_nickel_plating" }
      alloy = data&.dig(:treatment_data, "selected_alloy").presence || "unspecified"
      alloy.to_s.humanize
    rescue
      "Unspecified"
    end

    # ---- Parsing shared by anodiser / jigger boards ------------------------

    def vats_for(op)
      op["operation_text"].to_s[/vats? ([\d,\s]+)/i, 1].to_s.scan(/\d+/).map(&:to_i)
    end

    # "16V", "20 V" or "20V↗️45V" from the op text, normalised for display.
    def voltage_for(op)
      m = op["operation_text"].to_s[/(\d+(?:\.\d+)?\s*V(?:\s*↗️\s*\d+(?:\.\d+)?\s*V)?)\b/, 1]
      m&.gsub(/\s+/, "")
    end

    def minutes_for(op)
      op["operation_text"].to_s[/over (\d+) minutes/, 1]&.to_i
    end

    # Dye for THIS cycle: the first dye op after the anodising op, before the
    # next treatment starts. "Black dye for 25-30 minutes", markdown stripped.
    def dye_after(i)
      ops[(i + 1)..].each do |o|
        break if anodising_op?(o) || enp_op?(o)
        return o if dye_op?(o)
      end
      nil
    end

    def dye_label(i)
      op = dye_after(i)
      return nil unless op
      op["operation_text"].to_s.gsub(/\*+/, "").lines.first.to_s.strip.truncate(60)
    end

    def seal_op
      @seal_op ||= ops.find { |o| sealing_op?(o) }
    end

    def seal_label
      return "Unsealed" unless seal_op
      seal_op["operation_text"].to_s.gsub(/\*+/, "").lines.first.to_s.strip.truncate(70)
    end

    def signed_keys(op)
      (op["sign_offs"] || {}).keys - ["wo"]
    end

    # Nearest jig op before index i (each treatment cycle jigs itself).
    def jig_before(i)
      ops[0...i].reverse.find { |o| jig_op?(o) }
    end

    # ---- Anodisers: jigged, anodise outstanding ----------------------------

    def anodise_ready_rows(shop_vats)
      rows = []
      ops.each_with_index do |op, i|
        next unless anodising_op?(op)
        vats = vats_for(op)
        next if shop_vats.any? && (vats & shop_vats).empty?

        jig = jig_before(i)
        next unless jig
        ready = signed_keys(jig).reject { |b| (op["sign_offs"] || {}).key?(b) }
        next if ready.empty?

        rows << {
          job: self, op: op, vats: vats,
          voltage: voltage_for(op), minutes: minutes_for(op),
          dye: dye_label(i),
          seal: seal_label,
          batches: ready.sort_by(&:to_i),
          batch_qtys: batch_qtys(op, ready),
        }
      end
      rows
    end

    # ---- Jiggers: jig itself outstanding -----------------------------------

    # Contract review is WO-scoped (signed under the "wo" key). Nothing hits
    # a jiggers board until it's signed - an unfrozen record has no
    # sign-offs, so unreviewed work stays off the boards automatically.
    def contract_reviewed?
      # The first write to a record freezes it, so an unfrozen record cannot
      # carry a signed review. Bailing out here also keeps this cheap for the
      # navbar count: it avoids operations_for_display regenerating the live
      # route from the part for every unfrozen WO.
      return false unless frozen?
      cr = ops.find { |o| o["process_type"] == "contract_review" || o["id"] == "CONTRACT_REVIEW" }
      cr.present? && (cr["sign_offs"] || {}).key?("wo")
    end

    # Contract Review board membership: never released, review not signed.
    # (Releases can't exist without a signed review anyway - the empty check
    # is belt and braces against legacy/paper-era records.)
    def awaiting_contract_review?
      !contract_reviewed? && @wo.release_notes.empty?
    end

    def jig_queue_rows(shop_vats)
      return [] unless contract_reviewed?
      rows = []
      ops.each_with_index do |op, i|
        next unless jig_op?(op)
        nxt = ops[(i + 1)..].find { |o| vats_for(o).any? }
        next unless nxt
        next if shop_vats.any? && (vats_for(nxt) & shop_vats).empty?

        owner = @wo.process_record_owner
        total = frozen? ? owner.section_batch_count(owner.section_for_op(op)) : 1
        pending = (1..total).map(&:to_s) - signed_keys(op)
        next if pending.empty?

        rows << {
          job: self, jig_op: op, next_op: nxt,
          vats: vats_for(nxt),
          batches: frozen? ? pending.sort_by(&:to_i) : [],
        }
      end
      rows
    end

    def batch_qtys(op, keys)
      return {} unless frozen?
      owner = @wo.process_record_owner
      section = owner.section_for_op(op)
      keys.index_with { |k| owner.section_batch_qty(section, k) }
    rescue
      {}
    end
  end
end
