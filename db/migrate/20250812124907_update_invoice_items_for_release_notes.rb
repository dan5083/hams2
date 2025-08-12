class UpdateInvoiceItemsForReleaseNotes < ActiveRecord::Migration[8.0]
  def change
    # Add the foreign key constraint we couldn't add before
    add_foreign_key :invoice_items, :release_notes, column: :release_note_id
  end
end
