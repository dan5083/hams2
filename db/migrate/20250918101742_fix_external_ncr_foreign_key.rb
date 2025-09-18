class FixExternalNcrForeignKey < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :external_ncrs, :works_orders
    remove_column :external_ncrs, :works_order_id
    add_column :external_ncrs, :release_note_id, :uuid, null: false
    add_index :external_ncrs, :release_note_id
    add_foreign_key :external_ncrs, :release_notes
  end
end
