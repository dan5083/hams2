# db/migrate/20250812_create_parts.rb
class CreateParts < ActiveRecord::Migration[8.0]
  def change
    create_table :parts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Link to customer who owns this part
      t.references :customer, null: false, foreign_key: { to_table: :organizations }, type: :uuid

      # Part identification
      t.string :uniform_part_number, null: false
      t.string :uniform_part_issue, null: false, default: 'A'

      # Additional part info
      t.string :description
      t.string :material
      t.text :specification
      t.text :notes

      # Status
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :parts, [:customer_id, :uniform_part_number, :uniform_part_issue],
              unique: true,
              name: 'index_parts_on_customer_and_part_number_and_issue'
    add_index :parts, :uniform_part_number
    add_index :parts, :enabled
  end
end
