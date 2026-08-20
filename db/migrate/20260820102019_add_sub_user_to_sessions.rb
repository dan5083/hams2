class AddSubUserToSessions < ActiveRecord::Migration[8.0]
  def change
    add_reference :sessions, :sub_user, null: true, foreign_key: true
    add_column :sessions, :sub_user_started_at,   :datetime
    add_column :sessions, :sub_user_last_seen_at, :datetime
  end
end
