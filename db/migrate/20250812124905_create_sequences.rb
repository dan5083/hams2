class CreateSequences < ActiveRecord::Migration[8.0]
  def change
    create_table :sequences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.integer :value, null: false, default: 1

      t.timestamps
    end

    add_index :sequences, :key, unique: true

    # Seed initial sequences
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO sequences (id, key, value, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'works_order_number', 1000, NOW(), NOW()),
            (gen_random_uuid(), 'release_note_number', 1000, NOW(), NOW());
        SQL
      end
    end
  end
end
