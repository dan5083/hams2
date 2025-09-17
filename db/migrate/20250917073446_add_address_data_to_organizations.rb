class AddAddressDataToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :address_data, :jsonb, default: {}

    # Add GIN index for JSONB operations
    add_index :organizations, :address_data, using: :gin

    # Add index for customers only (if not already exists)
    add_index :organizations, :is_customer, where: "is_customer = true", if_not_exists: true
  end
end
