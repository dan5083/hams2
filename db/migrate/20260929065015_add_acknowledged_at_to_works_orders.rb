# db/migrate/<timestamp>_add_acknowledged_at_to_works_orders.rb
#
# When the order acknowledgement email covering this works order went out.
# Sent on contract-review sign-off (not at booking); nil until then.
class AddAcknowledgedAtToWorksOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :works_orders, :acknowledged_at, :datetime
  end
end
