# db/migrate/20250812_create_invoice_items.rb
class CreateInvoiceItems < ActiveRecord::Migration[8.0]
  def change
    create_table :invoice_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Link to invoice
      t.references :invoice, null: false, foreign_key: true, type: :uuid

      # Source references (for future when you add release_notes table)
      t.uuid :release_note_id, null: true # Will add foreign key later
      t.uuid :additional_charge_id, null: true # For future additional charges

      # Line item type
      t.string :kind, null: false # 'main', 'additional', 'manual'

      # Item details
      t.integer :quantity, null: false
      t.text :description, null: false

      # Pricing (ex-tax, tax, inc-tax)
      t.decimal :line_amount_ex_tax, precision: 10, scale: 2, null: false
      t.decimal :line_amount_tax, precision: 10, scale: 2, null: false
      t.decimal :line_amount_inc_tax, precision: 10, scale: 2, null: false

      # Ordering
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :invoice_items, [:invoice_id, :position]
    add_index :invoice_items, :release_note_id
    add_index :invoice_items, :kind

    # Constraints to ensure data integrity
    execute <<-SQL
      ALTER TABLE invoice_items
      ADD CONSTRAINT check_positive_amounts
      CHECK (line_amount_ex_tax >= 0 AND line_amount_tax >= 0 AND line_amount_inc_tax >= 0);
    SQL

    execute <<-SQL
      ALTER TABLE invoice_items
      ADD CONSTRAINT check_positive_quantity
      CHECK (quantity > 0);
    SQL
  end
end
