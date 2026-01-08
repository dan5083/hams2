class RemoveTransportMethodFromWorksOrders < ActiveRecord::Migration[8.0]
  def change
    remove_column :works_orders, :transport_method_id, :integer
  end
end
