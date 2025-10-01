class AddCustomerReferenceToWorksOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :works_orders, :customer_reference, :string
    add_index :works_orders, :customer_reference
  end
end
