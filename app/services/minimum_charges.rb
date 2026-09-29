# app/services/minimum_charges.rb
#
# Minimum charges are NOT baked into works-order prices. A works order always
# carries the true price (the PO's, else the part's, else £0 for the reviewer
# to fix). The minimums are then applied on top as additional charges, so the
# invoice reads "parts £68.00, minimum order charge £182.00" — which is what
# the customer has been told — and the part's real price is never lost.
#
# Two minimums, both applied here after booking:
#
#   per works order — Organization#minimum_works_order_charge, the one
#     per-customer setting (nil = none). Any live WO under it gets a
#     "Minimum works order charge" top-up for the difference, on that WO.
#   per customer order — a fixed rule: £250, or £125 when every WO on the
#     order is chemical conversion only. If the order's total (line prices +
#     WO top-ups) is under it, ONE "Minimum order charge" top-up for the
#     difference goes on the first WO.
#
# Idempotent: re-running recomputes both top-ups from scratch, so it is safe
# to call again after a WO is added, repriced or voided. Both presets are
# one-off charges, billed once per WO (Invoice.stage_to_date), unlike
# carriage which is billed per release.
class MinimumCharges
  DEFAULT_ORDER_MOC          = BigDecimal("250")
  CHEM_CONV_ORDER_MOC        = BigDecimal("125")
  CHEM_CONV_TREATMENT_TYPES  = %w[chemical_conversion].freeze

  PRESET_NAMES = {
    order:       "Minimum order charge",
    works_order: "Minimum works order charge"
  }.freeze

  def self.apply!(customer_order)
    new(customer_order).apply!
  end

  def initialize(customer_order)
    @order    = customer_order
    @customer = customer_order.customer
    @wos      = customer_order.works_orders.active.order(:number).to_a
  end

  # Returns { works_order_top_ups: { "WO123" => 12.5 }, order_top_up: 182.0 } (zeros omitted).
  def apply!
    return {} if @wos.empty?
    order_preset = preset(:order)
    wo_preset    = preset(:works_order)

    result = { works_order_top_ups: {} }
    WorksOrder.transaction do
      wo_min = @customer.minimum_works_order_charge
      @wos.each do |wo|
        top_up = wo_min.present? ? [wo_min - line_price(wo), 0].max : 0
        set_charge!(wo, wo_preset, top_up)
        result[:works_order_top_ups][wo.display_name] = top_up.to_f if top_up.positive?
      end

      total = @wos.sum { |wo| line_price(wo) + (result[:works_order_top_ups][wo.display_name] || 0) }
      order_top_up = [order_moc - total, 0].max
      @wos.each_with_index { |wo, i| set_charge!(wo, order_preset, i.zero? ? order_top_up : 0) }
      result[:order_top_up] = order_top_up.to_f if order_top_up.positive?
    end
    result
  end

  def order_moc
    @wos.all? { |wo| chem_conv_only?(wo.part) } ? CHEM_CONV_ORDER_MOC : DEFAULT_ORDER_MOC
  end

  private

  def line_price(wo)
    BigDecimal((wo.lot_price || 0).to_s)
  end

  def chem_conv_only?(part)
    types = part.parse_treatments_data.map { |t| t["type"] }.reject { |t| t == "stripping_only" }
    types.any? && types.all? { |t| CHEM_CONV_TREATMENT_TYPES.include?(t) }
  rescue StandardError
    false
  end

  # Put `amount` of `preset` on the WO (replacing any earlier value), or
  # remove it when the amount is zero. Other charges on the WO are untouched.
  def set_charge!(wo, preset, amount)
    ids     = Array(wo.selected_charge_ids).map(&:to_s).reject(&:blank?)
    amounts = (wo.custom_amounts || {}).dup
    if amount.positive?
      ids << preset.id.to_s unless ids.include?(preset.id.to_s)
      amounts[preset.id.to_s] = amount.round(2).to_f
    else
      ids.delete(preset.id.to_s)
      amounts.delete(preset.id.to_s)
    end
    return if ids == Array(wo.selected_charge_ids).map(&:to_s) && amounts == (wo.custom_amounts || {})
    wo.update!(selected_charge_ids: ids, custom_amounts: amounts)
  end

  def preset(key)
    AdditionalChargePreset.find_by(name: PRESET_NAMES.fetch(key)) or
      raise "AdditionalChargePreset '#{PRESET_NAMES[key]}' is missing — run the SetUpMinimumCharges migration"
  end
end
