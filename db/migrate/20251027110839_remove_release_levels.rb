class RemoveReleaseLevels < ActiveRecord::Migration[8.0]
  def up
    # Remove foreign key and column from works_orders
    remove_foreign_key :works_orders, :release_levels
    remove_column :works_orders, :release_level_id

    # Drop the release_levels table
    drop_table :release_levels
  end

  def down
    # In case you need to rollback
    create_table :release_levels, id: :uuid do |t|
      t.string :name, null: false
      t.text :statement, null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end

    add_index :release_levels, :name, unique: true
    add_index :release_levels, :enabled

    add_reference :works_orders, :release_level, type: :uuid, foreign_key: true
  end
end
