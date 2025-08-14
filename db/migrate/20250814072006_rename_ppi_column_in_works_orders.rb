# Create this file as: db/migrate/[timestamp]_rename_ppi_column_in_works_orders.rb

class RenamePpiColumnInWorksOrders < ActiveRecord::Migration[8.0]
  def change
    # Rename the foreign key column to match the original design
    rename_column :works_orders, :part_processing_instruction_id, :ppi_id

    # Update the index name to match the new column name
    remove_index :works_orders, name: "index_works_orders_on_ppi_id"
    add_index :works_orders, :ppi_id, name: "index_works_orders_on_ppi_id"
  end
end
