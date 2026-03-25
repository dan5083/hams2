# db/migrate/XXXXXX_create_xero_tokens.rb
# Run: rails generate migration CreateXeroTokens
# Then replace the contents with this

class CreateXeroTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :xero_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :tenant_id, null: false
      t.string :tenant_name
      t.string :access_token, null: false
      t.string :refresh_token, null: false
      t.datetime :expires_at, null: false
      t.jsonb :token_data, default: {}
      t.timestamps
    end

    add_index :xero_tokens, :tenant_id, unique: true
  end
end
