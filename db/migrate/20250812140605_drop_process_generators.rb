class DropProcessGenerators < ActiveRecord::Migration[8.0]
  def up
    # Remove the foreign key constraint from part_processing_instructions
    remove_foreign_key :part_processing_instructions, :process_generators

    # Remove whatever column references process_generators
    if column_exists?(:part_processing_instructions, :process_generator_id)
      remove_column :part_processing_instructions, :process_generator_id
    end

    # Add the new process_type column for our Ruby-based system
    add_column :part_processing_instructions, :process_type, :string

    # Drop the process_generators table - we don't want it anymore
    drop_table :process_generators
  end

  def down
    # We don't want to recreate this system, but Rails requires a down method
    raise ActiveRecord::IrreversibleMigration, "We don't want process_generators anymore"
  end
end
