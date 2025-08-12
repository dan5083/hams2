class CreateReleaseLevels < ActiveRecord::Migration[8.0]
  def change
    create_table :release_levels, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.text :statement, null: false # What this release level means
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :release_levels, :name, unique: true
    add_index :release_levels, :enabled
  end
end
