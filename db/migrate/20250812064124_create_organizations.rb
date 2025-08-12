class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name
      t.boolean :enabled
      t.boolean :is_customer
      t.boolean :is_supplier
      t.references :xero_contact, null: false, foreign_key: true

      t.timestamps
    end
  end
end
