class ConvertToUuids < ActiveRecord::Migration[8.0]
  def up
    # Clear existing data first (safe since it's just test data)
    Session.delete_all
    Organization.delete_all
    XeroContact.delete_all
    User.delete_all

    # Drop tables in dependency order
    drop_table :sessions
    drop_table :organizations
    drop_table :xero_contacts
    drop_table :users

    # Recreate with UUID primary keys
    create_table :users, id: :uuid, default: 'gen_random_uuid()' do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :username
      t.string :full_name
      t.boolean :enabled
      t.timestamps

      t.index :email_address, unique: true
    end

    create_table :xero_contacts, id: :uuid, default: 'gen_random_uuid()' do |t|
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

    create_table :organizations, id: :uuid, default: 'gen_random_uuid()' do |t|
      t.string :name
      t.boolean :enabled
      t.boolean :is_customer
      t.boolean :is_supplier
      t.uuid :xero_contact_id, null: false
      t.timestamps

      t.index :xero_contact_id
    end

    create_table :sessions, id: :uuid, default: 'gen_random_uuid()' do |t|
      t.uuid :user_id, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps

      t.index :user_id
    end

    # Add foreign keys
    add_foreign_key :organizations, :xero_contacts
    add_foreign_key :sessions, :users
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
