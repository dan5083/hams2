class CreateAiAssistantRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_assistant_requests, id: :uuid do |t|
      t.uuid   :user_id,   null: false
      t.string :status,    null: false, default: "pending"  # pending | complete | error
      t.jsonb  :messages,  null: false, default: []
      t.text   :response
      t.text   :error
      t.timestamps
    end

    add_index :ai_assistant_requests, :user_id
    add_index :ai_assistant_requests, :status
    add_index :ai_assistant_requests, :created_at

    # Auto-clean requests older than 24 hours via a scope — no sensitive data lingers
  end
end
