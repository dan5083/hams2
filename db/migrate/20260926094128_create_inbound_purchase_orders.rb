class CreateInboundPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :inbound_purchase_orders do |t|
      t.string   :mailgun_message_id, null: false   # Message-Id header — idempotency key
      t.string   :message_url                        # Mailgun stored-message URL (3-day retention)
      t.string   :sender                             # envelope sender
      t.string   :from_header                        # "Jane Buyer <jane@customer.com>"
      t.string   :recipient
      t.string   :subject
      t.text     :body_plain
      t.text     :stripped_text                      # body minus quoted replies/signature
      t.datetime :received_at
      t.jsonb    :headers,     null: false, default: {}
      t.jsonb    :attachments, null: false, default: []  # [{index,name,content_type,size,mailgun_url,public_id,secure_url}]

      # received → fetching → analysing → needs_review | already_on_file | ignored | error
      #                                  → booked | dismissed (after human review)
      t.string   :status, null: false, default: "received"
      t.jsonb    :proposal, null: false, default: {}  # assistant's structured read of the PO
      t.text     :summary                             # human-readable outcome / reason
      t.text     :error

      t.references :ai_assistant_request, foreign_key: true, null: true
      t.references :customer_order,       foreign_key: true, null: true
      t.references :reviewed_by,          foreign_key: { to_table: :users }, null: true
      t.datetime   :reviewed_at

      t.timestamps
    end

    add_index :inbound_purchase_orders, :mailgun_message_id, unique: true
    add_index :inbound_purchase_orders, :status
  end
end
