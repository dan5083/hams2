class DropTransportMethods < ActiveRecord::Migration[8.0]
  def up
    drop_table :transport_methods
  end

  def down
    create_table :transport_methods, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.boolean :enabled, default: true, null: false
      t.text :description
      t.timestamps
    end

    add_index :transport_methods, :name, unique: true
    add_index :transport_methods, :enabled
  end
end
