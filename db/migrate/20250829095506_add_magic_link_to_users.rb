class AddMagicLinkToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :magic_link_token, :string
    add_column :users, :magic_link_expires_at, :datetime

    # Add indexes for performance and uniqueness
    add_index :users, :magic_link_token, unique: true, where: "magic_link_token IS NOT NULL"
    add_index :users, :magic_link_expires_at
  end
end
