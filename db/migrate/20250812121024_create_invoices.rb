class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Link to organization (customer)
      t.references :customer, null: false, foreign_key: { to_table: :organizations }, type: :uuid

      # Invoice details
      t.date :date, null: false, default: -> { 'CURRENT_DATE' }
      t.decimal :total_ex_tax, precision: 10, scale: 2, null: false, default: 0
      t.decimal :total_tax, precision: 10, scale: 2, null: false, default: 0
      t.decimal :total_inc_tax, precision: 10, scale: 2, null: false, default: 0

      # Tax information (from Xero)
      t.string :xero_tax_type, null: false
      t.decimal :tax_rate_pct, precision: 5, scale: 2, null: false

      # Xero integration fields
      t.string :xero_id, null: true # Set after successful push to Xero
      t.string :number, null: true # Xero-generated invoice number
      t.jsonb :xero_data, default: {}
      t.datetime :last_synced_at

      # Status tracking
      t.string :status, default: 'draft' # draft, pushed_to_xero, synced
      t.boolean :voided, default: false

      t.timestamps
    end

    add_index :invoices, :xero_id, unique: true, where: "xero_id IS NOT NULL"
    add_index :invoices, :number, unique: true, where: "number IS NOT NULL"
    add_index :invoices, :date
    add_index :invoices, :status
  end
end
