class AddFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :username, :string
    add_column :users, :full_name, :string
    add_column :users, :enabled, :boolean, default: true, null: false

    # Add indexes
    add_index :users, :username, unique: true
    add_index :users, :enabled

    # Populate existing users with default values
    reversible do |dir|
      dir.up do
        # Set username from email (before @ symbol) and full_name placeholder
        execute <<-SQL
          UPDATE users
          SET username = SPLIT_PART(email_address, '@', 1),
              full_name = 'User ' || SPLIT_PART(email_address, '@', 1),
              enabled = true
          WHERE username IS NULL;
        SQL
      end
    end

    # Make fields not null after populating
    change_column_null :users, :username, false
    change_column_null :users, :full_name, false
  end
end
