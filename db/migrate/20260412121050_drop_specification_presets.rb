# db/migrate/xxxx_drop_specification_presets.rb
class DropSpecificationPresets < ActiveRecord::Migration[8.0]
  def up
    drop_table :specification_presets
  end

  def down
    create_table :specification_presets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.text :content, null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
      t.index :enabled
      t.index :name, unique: true
    end
  end
end
