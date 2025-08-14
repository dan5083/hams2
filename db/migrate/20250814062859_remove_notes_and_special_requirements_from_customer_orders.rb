class RemoveNotesAndSpecialRequirementsFromCustomerOrders < ActiveRecord::Migration[8.0]
  def change
    remove_column :customer_orders, :notes, :text
  end
end
