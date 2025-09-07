class RenamePartNumberColumns < ActiveRecord::Migration[8.0]
  def change
    rename_column :parts, :uniform_part_number, :part_number
    rename_column :parts, :uniform_part_issue, :part_issue

    # Update the unique index to use new column names
    remove_index :parts, name: "index_parts_on_customer_and_part_number_and_issue"
    add_index :parts, [:customer_id, :part_number, :part_issue],
              unique: true,
              name: "index_parts_on_customer_and_part_number_and_issue"
  end
end
