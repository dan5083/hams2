class DropPartProcessingInstructionsTable < ActiveRecord::Migration[8.0]
  def change
    drop_table :part_processing_instructions do |t|
      # Define the table structure for reversibility
      t.uuid :part_id, null: false
      t.uuid :customer_id, null: false
      t.string :part_number, null: false
      t.string :part_issue, null: false
      t.string :part_description
      t.text :specification
      t.text :special_instructions
      t.jsonb :customisation_data, default: {}
      t.boolean :enabled, default: true, null: false
      t.uuid :replaces_id
      t.string :process_type
      t.timestamps

      t.index [:customer_id]
      t.index [:enabled]
      t.index [:part_id]
      t.index [:part_number, :part_issue]
      t.index [:replaces_id]
    end
  end
end
