# db/migrate/XXXXXXXXXXXXXX_add_user_to_sub_users.rb
# (generate with `rails g migration AddUserToSubUsers` and paste the body in,
# or rename this file with a real timestamp)
class AddUserToSubUsers < ActiveRecord::Migration[8.0]
  def change
    # users is uuid-keyed, sub_users is bigint, so the type must be explicit.
    # Nullable: floor operators have no login. Unique: a person is one operator.
    add_reference :sub_users, :user,
                  type: :uuid,
                  null: true,
                  foreign_key: true,
                  index: { unique: true }
  end
end
