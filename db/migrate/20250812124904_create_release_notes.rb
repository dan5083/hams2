class CreateReleaseNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :release_notes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Sequential number for release notes
      t.integer :number, null: false

      # Links
      t.references :works_order, null: false, foreign_key: true, type: :uuid
      t.references :issued_by, null: false, foreign_key: { to_table: :users }, type: :uuid

      # Release details
      t.date :date, null: false
      t.integer :quantity_accepted, null: false, default: 0
      t.integer :quantity_rejected, null: false, default: 0

      # Notes and special handling
      t.text :remarks
      t.boolean :no_invoice, null: false, default: false # Don't invoice this release

      # Status
      t.boolean :voided, null: false, default: false

      t.timestamps
    end

    add_index :release_notes, :number, unique: true
    add_index :release_notes, :date
    add_index :release_notes, :voided
    add_index :release_notes, :no_invoice

    # Constraints
    execute <<-SQL
      ALTER TABLE release_notes
      ADD CONSTRAINT check_positive_quantities
      CHECK (quantity_accepted >= 0 AND quantity_rejected >= 0);
    SQL

    execute <<-SQL
      ALTER TABLE release_notes
      ADD CONSTRAINT check_has_quantity
      CHECK (quantity_accepted > 0 OR quantity_rejected > 0);
    SQL
  end
end
