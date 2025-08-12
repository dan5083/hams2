class CreatePartProcessingInstructions < ActiveRecord::Migration[8.0]
  def change
    create_table :part_processing_instructions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Links
      t.references :part, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: { to_table: :organizations }, type: :uuid
      t.references :process_generator, null: false, foreign_key: true, type: :uuid

      # Part details (duplicated for historical tracking)
      t.string :part_number, null: false
      t.string :part_issue, null: false
      t.string :part_description

      # Processing details
      t.text :specification
      t.text :special_instructions

      # Customization data (how this part customizes the base process)
      t.jsonb :customisation_data, default: {}

      # Status and versioning
      t.boolean :enabled, null: false, default: true
      t.references :replaces, null: true, foreign_key: { to_table: :part_processing_instructions }, type: :uuid

      t.timestamps
    end

    add_index :part_processing_instructions, :enabled
    add_index :part_processing_instructions, [:part_number, :part_issue]
  end
end
