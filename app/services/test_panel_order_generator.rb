# app/services/test_panel_order_generator.rb
#
# Monthly HASTL test panel order. Replaces the Word doc Chris Connon edits and
# Julia hand-books: the only things that change month to month are the order
# name and the panel numbers in the customer references, so both are derived.
#
#   TestPanelOrderGenerator.ensure_upcoming!            # Heroku Scheduler, daily
#   TestPanelOrderGenerator.new(Date.new(2026, 11, 1)).preview   # dry run
#   TestPanelOrderGenerator.new(Date.new(2026, 11, 1)).create!   # by hand
#
# Panel numbering: every panel group gets the next P-number in sequence, and
# the sequence is picked up from the highest P#### already used on any HASTL
# works order, so the generator carries on exactly where the paper trail left
# off. A part with groups [3, 1] gets "P3251.1-3. P3252"; [5] gets "P3250.1-5";
# [1] gets "P3265". Quantity is the sum of the groups.
#
# Template taken verbatim from OCTOBER 2026 (36a1f34f-8da2-424c-802e-68a3bf2e30f8).
# Edit TEMPLATE when the lab changes the panel schedule.
class TestPanelOrderGenerator
  CUSTOMER_NAME = "HASTL".freeze

  Line = Struct.new(:part_id, :groups, :label)

  TEMPLATE = [
    Line.new("ed02271a-954c-45c2-b88a-4f6fc77644ca", [5],    "SULPHURIC ACID ANODISE + SEAL IN DICHROMATE"),
    Line.new("56454524-cdd2-42c9-9000-10389bb77577", [3, 1], "SULPHURIC ACID ANODISE (UNSEALED)"),
    Line.new("721e5498-1e2e-4a80-ae8a-585e5a4202db", [3],    "HARD ANODISE VAT 2 UNSEALED 4x4"),
    Line.new("85a8f189-97de-4f17-a249-65ed4c7707b3", [3],    "HARD ANODISE VAT 2 UNSEALED 3x3"),
    Line.new("ec5aa0ca-924b-4fc5-9c73-679dd95cf25e", [5],    "HARD ANODISE 10 MINS HOT WATER SEAL"),
    Line.new("41f05608-97b1-4740-8b27-d8ee1a7f7293", [5],    "HARD ANODISE 10 MINS DICHROMATE SEAL 3x10"),
    Line.new("a97dd39c-cc82-456b-9d3d-73ce33ded2ce", [5],    "CHROMIC PROCESS 1 HOT WATER SEAL 3x10"),
    Line.new("f9833d46-1e71-4355-ab1e-3a323a0e4148", [3, 1], "CHROMIC PROCESS 1 UNSEALED 3x3"),
    Line.new("857d552e-476e-49d9-ab7f-648148d107e4", [5],    "CHROMIC PROCESS 2 HOT WATER SEAL 3x10"),
    Line.new("bc5372fe-6956-4276-8e0a-d2060069b29e", [3, 1], "CHROMIC PROCESS 2 UNSEALED 3x3"),
    Line.new("91bafb54-e10f-4f31-88ee-c0bdb2491737", [5, 3], "ALOCROM 1200 3x10"),
    Line.new("2c85a4ac-99ac-475b-9412-edc259081a21", [1],    "ALOCROM 1200 8x4"),
    Line.new("ead03e1b-3b11-4c27-b632-e92c45d7efb4", [5],    "SURTEC 650"),
    Line.new("e514c85f-5480-4d1e-8808-8760b7932c62", [5],    "IRRIDITE NCP"),
    Line.new("a53e879f-da65-4b93-aae4-4fdca3d69ac0", [5],    "IRRIDITE TCP 3"),
    Line.new("a2bcce7a-1afc-4432-b46b-2b51db52a9ef", [4, 1], "ENP VAND-ALOY 4100 HIGH PHOS ON 2024"),
    Line.new("0e004b17-bc24-4015-b897-02d9924e4c9d", [1, 1], "ENP NIKLAD 767/808 MEDIUM PHOS ON 2024"),
    Line.new("0fd2d86c-0d0e-43fe-aec6-eb112a4f6fd2", [4],    "ENP HIGH PHOS ON LOW CARBON STEEL"),
    Line.new("c1add45f-814b-4df5-a0ba-e569d8eeb8c3", [4],    "ENP MEDIUM PHOS ON LOW CARBON STEEL"),
    Line.new("52c23a60-e416-4cf5-8df6-0fd5021f1a69", [4],    "HYDROGEN DE-EMBRITTLEMENT (STEEL MEDIUM PHOS)"),
    Line.new("750f5453-dd69-48b9-ab84-763dfdfac2fb", [1],    "66 MICROETCH"),
    Line.new("70edcad2-2d87-43c2-8b32-b589418f4c92", [1],    "KEYCOTE 245"),
  ].freeze

  # ---- Scheduler entry point ------------------------------------------------

  # Idempotent. Run daily; creates this month's order on the first run of the
  # month and does nothing thereafter.
  def self.ensure_upcoming!(today: Date.current, stamp_as: nil)
    gen = new(today.beginning_of_month, today: today)
    if gen.exists?
      Rails.logger.info "[TestPanels] #{gen.order_number} already exists - nothing to do"
      return nil
    end
    gen.create!(stamp_as: stamp_as)
  end

  # ---- Instance --------------------------------------------------------------

  attr_reader :month, :today

  def initialize(month, today: Date.current)
    @month = month.to_date.beginning_of_month
    @today = today
  end

  def customer
    @customer ||= Organization.find_by!(name: CUSTOMER_NAME)
  end

  # "NOVEMBER 2026 TEST PANELS"
  def order_number
    "#{month.strftime('%B').upcase} #{month.year} TEST PANELS"
  end

  # Matches the new name and the legacy bare "OCTOBER 2026" / "September 2026".
  def existing_order
    CustomerOrder.where(customer: customer, voided: false)
                 .where("number ILIKE ?", "#{month.strftime('%B')} #{month.year}%")
                 .first
  end

  def exists?
    existing_order.present?
  end

  # Highest P-number used on any HASTL works order to date.
  def last_panel_number
    WorksOrder.joins(:customer_order)
              .where(customer_orders: { customer_id: customer.id })
              .where("customer_reference ~ 'P[0-9]{3,}'")
              .pluck(:customer_reference)
              .flat_map { |r| r.scan(/P(\d{3,})/).flatten.map(&:to_i) }
              .max || 0
  end

  # [{ line:, part:, quantity:, customer_reference: }, ...] with the P-numbers
  # allocated in template order, starting after the last one used.
  def rows(from: last_panel_number + 1)
    n = from
    TEMPLATE.map do |line|
      refs = line.groups.map do |size|
        ref = size == 1 ? "P#{n}" : "P#{n}.1-#{size}"
        n += 1
        ref
      end
      { line: line, part: Part.find(line.part_id), quantity: line.groups.sum, customer_reference: refs.join(". ") }
    end
  end

  def panel_count
    TEMPLATE.sum { |l| l.groups.size }
  end

  # Dry run: prints what create! would do, writes nothing.
  def preview
    first = last_panel_number + 1
    puts "#{order_number}  (customer #{customer.name}, received #{today})"
    puts "exists already: #{existing_order.display_name}" if exists?
    puts "panels P#{first}-P#{first + panel_count - 1}"
    rows(from: first).each do |r|
      puts format("  qty %-2d %-24s %s (%s)", r[:quantity], r[:customer_reference], r[:part].part_number, r[:part].part_issue)
    end
    nil
  end

  # Creates the order and its works orders in one transaction. The WorksOrder
  # callbacks take care of part details, WO numbering, zero pricing and
  # auto-grouping same-route siblings - same as booking via the form.
  def create!(stamp_as: nil)
    raise "#{order_number} already exists (#{existing_order.display_name})" if exists?

    run_as(stamp_as) do
      CustomerOrder.transaction do
        order = CustomerOrder.create!(customer: customer, number: order_number, date_received: today)
        rows.each do |r|
          order.works_orders.create!(
            part: r[:part],
            quantity: r[:quantity],
            customer_reference: r[:customer_reference],
            price_type: "each",
            each_price: 0,
            lot_price: 0
          )
        end
        Rails.logger.info "[TestPanels] created #{order.display_name} with #{order.works_orders.count} works orders"
        order
      end
    end
  end

  private

  # Scheduler runs with no request, so Current.user is nil; optionally stamp
  # created_by/updated_by as a named user.
  def run_as(user)
    return yield unless user
    Current.set(user: user) { yield }
  end
end
