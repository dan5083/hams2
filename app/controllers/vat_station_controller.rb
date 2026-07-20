# app/controllers/vat_station_controller.rb
#
# Full-screen kiosk shown on the Beetronics touchscreen at the vat 2 panel.
# Read-only: the operator types a works order number and gets the electrical
# recipe. Nothing is written back — the route card is still the record.
class VatStationController < ApplicationController
  layout false

  # Which vat this screen is bolted to. Vat 2 for the first install; change the
  # constant (or set VAT_STATION_NUMBER in the env) when the next panel goes in.
  STATION_VAT = (ENV["VAT_STATION_NUMBER"] || 2).to_i

  def show
    @station_vat = STATION_VAT
    @query = params[:wo].to_s.strip.gsub(/\AWO/i, "")

    return if @query.blank?

    @works_order = WorksOrder.find_by(number: @query)

    if @works_order.nil?
      @error = "No works order #{@query}."
      return
    end

    if @works_order.voided?
      @error = "WO#{@works_order.number} is voided. Do not process."
      return
    end

    @cycles = HardAnodiseParser.cycles_for(@works_order)
    @error = "WO#{@works_order.number} has no hard anodising operation." if @cycles.blank?
  end
end
