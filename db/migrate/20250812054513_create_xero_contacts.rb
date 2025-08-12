class CreateXeroContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :xero_contacts do |t|
      t.string :name
      t.string :contact_status
      t.boolean :is_customer
      t.boolean :is_supplier
      t.string :merged_to_contact_id
      t.string :accounts_receivable_tax_type
      t.string :accounts_payable_tax_type
      t.string :xero_id
      t.jsonb :xero_data
      t.timestamp :last_synced_at

      t.timestamps
    end
  end
end
