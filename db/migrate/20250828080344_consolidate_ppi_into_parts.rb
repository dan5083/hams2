class ConsolidatePpiIntoParts < ActiveRecord::Migration[8.0]
  def change
    # Add only the missing PPI fields to parts table
    add_column :parts, :special_instructions, :text
    add_column :parts, :process_type, :string
    add_column :parts, :customisation_data, :jsonb, default: {}
    add_column :parts, :replaces_id, :uuid

    # Add foreign key for replaces relationship
    add_foreign_key :parts, :parts, column: :replaces_id
    add_index :parts, :replaces_id

    # Add index on customisation_data for performance
    add_index :parts, :customisation_data, using: :gin

    # Remove ppi_id from works_orders
    remove_foreign_key :works_orders, :part_processing_instructions
    remove_column :works_orders, :ppi_id, :uuid

    # Add indexes for performance
    add_index :parts, :process_type
    add_index :parts, [:customer_id, :enabled]
  end

  def down
    # Reverse the changes - only remove what we added
    add_column :works_orders, :ppi_id, :uuid, null: false
    add_foreign_key :works_orders, :part_processing_instructions, column: :ppi_id

    remove_index :parts, [:customer_id, :enabled]
    remove_index :parts, :process_type
    remove_index :parts, :customisation_data
    remove_index :parts, :replaces_id
    remove_foreign_key :parts, column: :replaces_id

    remove_column :parts, :special_instructions
    remove_column :parts, :process_type
    remove_column :parts, :customisation_data
    remove_column :parts, :replaces_id

    # Don't remove specification or enabled - they were already there
  end
end
