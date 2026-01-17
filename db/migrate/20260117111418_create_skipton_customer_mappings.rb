class CreateSkiptonCustomerMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :skipton_customer_mappings do |t|
      t.string :xero_name, null: false
      t.string :skipton_id, null: false

      t.timestamps
    end

    add_index :skipton_customer_mappings, :xero_name, unique: true
    add_index :skipton_customer_mappings, :skipton_id
  end
end
