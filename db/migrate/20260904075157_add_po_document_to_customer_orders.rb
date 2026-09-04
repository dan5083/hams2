class AddPoDocumentToCustomerOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_orders, :po_document, :jsonb
  end
end
