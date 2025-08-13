class RemoveExtraInvoiceFields < ActiveRecord::Migration[8.0]
  def change
    # Remove extra fields that Mike's design doesn't have
    remove_column :invoices, :status, :string
    remove_column :invoices, :voided, :boolean
    remove_column :invoices, :xero_data, :jsonb
    remove_column :invoices, :last_synced_at, :datetime

    # Remove indexes that are no longer needed
    remove_index :invoices, :status if index_exists?(:invoices, :status)

    # Also remove additional_charge_id from invoice_items since Mike uses it differently
    # and we're not implementing additional charges yet
    remove_column :invoice_items, :additional_charge_id, :uuid
  end

  def down
    # Add fields back if we need to rollback
    add_column :invoices, :status, :string, default: 'draft'
    add_column :invoices, :voided, :boolean, default: false
    add_column :invoices, :xero_data, :jsonb, default: {}
    add_column :invoices, :last_synced_at, :datetime

    add_index :invoices, :status

    add_column :invoice_items, :additional_charge_id, :uuid
  end
end
