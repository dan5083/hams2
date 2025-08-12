# db/migrate/20250812_create_process_generators.rb
class CreateProcessGenerators < ActiveRecord::Migration[8.0]
  def change
    create_table :process_generators, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true

      # Simple placeholder data for now - you'll expand this later
      # Instead of complex TipTap JSON, just store basic process info
      t.jsonb :process_data, default: {}

      # Future: You might add fields like:
      # t.text :validation_rules
      # t.jsonb :step_definitions, default: []
      # t.string :process_type # e.g., 'surface_treatment', 'machining', etc.

      t.timestamps
    end

    add_index :process_generators, :name
    add_index :process_generators, :enabled
  end
end
