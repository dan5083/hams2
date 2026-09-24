class CreateQuotes < ActiveRecord::Migration[8.0]
  def change
    create_table :quotes, id: :uuid do |t|
      t.integer :number, null: false
      t.references :customer, null: false, foreign_key: { to_table: :organizations }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string  :status, null: false, default: "draft" # draft | sent | won | lost
      t.string  :title
      t.text    :summary
      t.string  :enquirer_name
      t.string  :enquirer_email
      t.date    :valid_until
      t.datetime :sent_at
      t.string  :sent_to, array: true, default: []
      t.text    :notes
      t.string  :ai_request_id # AiAssistantRequest that produced it, for traceability
      t.timestamps
    end
    add_index :quotes, :number, unique: true
    add_index :quotes, :status

    create_table :quote_items, id: :uuid do |t|
      t.references :quote, null: false, foreign_key: true, type: :uuid
      t.references :part, foreign_key: true, type: :uuid
      t.integer :position, null: false, default: 0
      t.text    :description, null: false
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_amount, precision: 10, scale: 2, null: false, default: 0
      t.timestamps
    end
  end
end
