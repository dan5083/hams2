# db/migrate/<timestamp>_add_booking_notes_to_works_orders.rb
#
# Instructions that arrive with the PO (strip details, "omit seal", the
# unpriced-booking warning). Previously posted as a note on the contract
# review operation, which froze the process record and stopped the WO
# joining a process group. Rendered with the part's special instructions.
class AddBookingNotesToWorksOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :works_orders, :booking_notes, :text
  end
end
