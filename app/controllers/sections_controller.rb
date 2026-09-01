# app/controllers/sections_controller.rb
#
# Shop-floor section boards. Read-only; everything is derived per-request by
# ShopSectionBoard from operations_for_display, so there is nothing to keep
# in sync.
#
# Routes (add to config/routes.rb):
#   get "sections/:section", to: "sections#show", as: :section,
#       constraints: { section: Regexp.union(ShopSectionBoard::SECTIONS.keys) }
class SectionsController < ApplicationController
  def show
    @section = params[:section]
    @title = ShopSectionBoard::SECTIONS.fetch(@section) { raise ActionController::RoutingError, "No section #{@section}" }

    # Live work only: open, not voided, parts still to release. Grouped
    # members ride through on their lead's record inside the board.
    works_orders = WorksOrder.open
                             .with_unreleased_quantity
                             .includes(:process_group, :release_notes, part: [], customer_order: :customer)

    @board = ShopSectionBoard.new(works_orders)
  end
end
