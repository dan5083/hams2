class CreateInboundPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :inbound_purchase_orders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :mailgun_message_id, null: false
      t.string   :message_url
      t.string   :sender
      t.string   :from_header
      t.string   :recipient
      t.string   :subject
      t.text     :body_plain
      t.text     :stripped_text
      t.datetime :received_at
      t.jsonb    :headers,     null: false, default: {}
      t.jsonb    :attachments, null: false, default: []

      t.string   :status,   null: false, default: "received"
      t.jsonb    :proposal, null: false, default: {}
      t.text     :summary
      t.text     :error

      t.references :ai_assistant_request, type: :uuid, foreign_key: true, null: true
      t.references :customer_order,       type: :uuid, foreign_key: true, null: true
      t.references :reviewed_by,          type: :uuid, foreign_key: { to_table: :users }, null: true
      t.datetime   :reviewed_at

      t.timestamps
    end

    add_index :inbound_purchase_orders, :mailgun_message_id, unique: true
    add_index :inbound_purchase_orders, :status
  end
end
