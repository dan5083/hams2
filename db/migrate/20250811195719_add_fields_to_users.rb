class AddFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :username, :string
    add_column :users, :full_name, :string
    add_column :users, :enabled, :boolean
  end
end
