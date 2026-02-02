class CreateQualityDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :quality_documents do |t|
      t.string :document_type, null: false
      t.string :code, null: false
      t.string :title, null: false
      t.integer :current_issue_number, default: 1, null: false
      t.string :approved_by
      t.jsonb :content, default: {}

      t.timestamps
    end

    add_index :quality_documents, [:document_type, :code], unique: true
    add_index :quality_documents, :content, using: :gin

    create_table :quality_document_revisions do |t|
      t.references :quality_document, null: false, foreign_key: true
      t.integer :issue_number, null: false
      t.string :changed_by, null: false
      t.text :change_description
      t.jsonb :previous_content
      t.timestamp :changed_at, null: false
    end

    add_index :quality_document_revisions, [:quality_document_id, :issue_number]
  end
end
