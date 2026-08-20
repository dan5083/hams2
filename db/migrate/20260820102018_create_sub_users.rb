class CreateSubUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :sub_users do |t|
      t.string   :name,             null: false
      t.string   :pin_digest
      t.boolean  :enabled,          null: false, default: true
      t.integer  :failed_pin_count, null: false, default: 0
      t.datetime :pin_locked_until

      t.timestamps
    end

    add_index :sub_users, :name, unique: true
  end
end
