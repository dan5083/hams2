class AddAdditionalChargesToWorksOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :works_orders, :additional_charge_data, :jsonb, default: {}
    add_index :works_orders, :additional_charge_data, using: :gin
  end
end
