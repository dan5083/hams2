# db/migrate/20260330080454_create_external_ncr_release_notes.rb
class CreateExternalNcrReleaseNotes < ActiveRecord::Migration[8.0]
  def up
    create_table :external_ncr_release_notes, id: :uuid do |t|
      t.references :external_ncr, null: false, foreign_key: true, type: :uuid
      t.references :release_note, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :external_ncr_release_notes, [:external_ncr_id, :release_note_id],
              unique: true, name: 'idx_ncr_release_notes_unique'

    # Migrate existing data: copy release_note_id from external_ncrs into join table
    execute <<-SQL
      INSERT INTO external_ncr_release_notes (id, external_ncr_id, release_note_id, created_at, updated_at)
      SELECT gen_random_uuid(), id, release_note_id, NOW(), NOW()
      FROM external_ncrs
      WHERE release_note_id IS NOT NULL
    SQL

    # Make release_note_id nullable (keep column for rollback safety, remove in a later migration)
    change_column_null :external_ncrs, :release_note_id, true
  end

  def down
    # Restore release_note_id from join table (take first associated RN per NCR)
    execute <<-SQL
      UPDATE external_ncrs
      SET release_note_id = (
        SELECT release_note_id
        FROM external_ncr_release_notes
        WHERE external_ncr_release_notes.external_ncr_id = external_ncrs.id
        ORDER BY created_at ASC
        LIMIT 1
      )
    SQL

    change_column_null :external_ncrs, :release_note_id, false

    drop_table :external_ncr_release_notes
  end
end
