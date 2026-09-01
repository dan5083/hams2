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
    "shop1"    => [1, 2, 3, 9, 12],
    "shop2"    => [5, 6],
    "factory2" => [],                   # TODO Dan: which vats are in Factory 2?
  }.freeze

  SECTIONS = {
    "enp"             => "ENP",
    "shop1_anodisers" => "Shop 1 · Anodisers",
    "shop2_anodisers" => "Shop 2 · Anodisers",
    "shop1_jiggers"   => "Shop 1 · Jiggers",
    "shop2_jiggers"   => "Shop 2 · Jiggers",
    "factory2"        => "Factory 2",
  }.freeze

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

    # ---- ENP ---------------------------------------------------------------

    def enp_op
      @enp_op ||= ops.find { |o| o["process_type"] == "electroless_nickel_plating" }
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

    # "16V" or "20V↗️45V" verbatim from the op text.
    def voltage_for(op)
      op["operation_text"].to_s[/(\d+(?:\.\d+)?V(?:↗️\d+(?:\.\d+)?V)?)/, 1]
    end

    def minutes_for(op)
      op["operation_text"].to_s[/over (\d+) minutes/, 1]&.to_i
    end

    # Dye for THIS cycle: the first dye op after the anodising op, before the
    # next treatment starts. "Black dye for 25-30 minutes", markdown stripped.
    def dye_after(i)
      ops[(i + 1)..].each do |o|
        break if ANODISING_TYPES.include?(o["process_type"]) || o["process_type"] == "electroless_nickel_plating"
        return o if o["process_type"] == "dye"
      end
      nil
    end

    def dye_label(i)
      op = dye_after(i)
      return nil unless op
      op["operation_text"].to_s.gsub(/\*+/, "").lines.first.to_s.strip.truncate(60)
    end

    def seal_op
      @seal_op ||= ops.find { |o| %w[sealing dichromate_sealing].include?(o["process_type"]) }
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
      ops[0...i].reverse.find { |o| o["process_type"] == "jig" }
    end

    # ---- Anodisers: jigged, anodise outstanding ----------------------------

    def anodise_ready_rows(shop_vats)
      rows = []
      ops.each_with_index do |op, i|
        next unless ANODISING_TYPES.include?(op["process_type"])
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
      cr = ops.find { |o| o["process_type"] == "contract_review" || o["id"] == "CONTRACT_REVIEW" }
      cr.present? && (cr["sign_offs"] || {}).key?("wo")
    end

    def jig_queue_rows(shop_vats)
      return [] unless contract_reviewed?
      rows = []
      ops.each_with_index do |op, i|
        next unless op["process_type"] == "jig"
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
