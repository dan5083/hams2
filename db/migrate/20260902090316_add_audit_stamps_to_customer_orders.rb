class AddAuditStampsToCustomerOrders < ActiveRecord::Migration[8.0]
  def change
    add_reference :customer_orders, :created_by,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :users }
    add_reference :customer_orders, :updated_by,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :users }
  end
end
