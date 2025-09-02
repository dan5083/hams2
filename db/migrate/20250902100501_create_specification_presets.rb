# db/migrate/20250102120000_create_specification_presets.rb
class CreateSpecificationPresets < ActiveRecord::Migration[8.0]
  def change
    create_table :specification_presets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.text :content, null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps

      t.index [:enabled], name: "index_specification_presets_on_enabled"
      t.index [:name], name: "index_specification_presets_on_name", unique: true
    end
  end
end
