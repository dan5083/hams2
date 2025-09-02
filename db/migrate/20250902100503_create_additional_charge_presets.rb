# db/migrate/20250102120001_create_additional_charge_presets.rb
class CreateAdditionalChargePresets < ActiveRecord::Migration[8.0]
  def change
    create_table :additional_charge_presets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :amount, precision: 10, scale: 2
      t.boolean :is_variable, default: false, null: false
      t.string :calculation_type
      t.boolean :enabled, default: true, null: false
      t.timestamps

      t.index [:enabled], name: "index_additional_charge_presets_on_enabled"
      t.index [:name], name: "index_additional_charge_presets_on_name", unique: true
      t.index [:is_variable], name: "index_additional_charge_presets_on_is_variable"
    end
  end
end
