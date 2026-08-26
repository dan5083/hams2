class AddPinLookupToSubUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :sub_users, :pin_lookup, :string
    add_index  :sub_users, :pin_lookup, unique: true
  end
end
