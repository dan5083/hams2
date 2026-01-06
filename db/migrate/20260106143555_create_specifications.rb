class CreateSpecifications < ActiveRecord::Migration[8.0]
  def change
    create_table :specifications, id: :uuid do |t|
      t.string :title, null: false
      t.text :description
      t.string :spec_number
      t.string :version
      t.boolean :is_qs, default: false, null: false
      t.boolean :archived, default: false, null: false
      t.jsonb :document_data, default: {}, null: false

      t.uuid :created_by_id, null: false
      t.uuid :updated_by_id

      t.timestamps
    end

    add_index :specifications, :title
    add_index :specifications, :spec_number, unique: true, where: "spec_number IS NOT NULL"
    add_index :specifications, :is_qs
    add_index :specifications, :archived
    add_index :specifications, :created_by_id
    add_index :specifications, :updated_by_id
    add_index :specifications, :document_data, using: :gin

    add_foreign_key :specifications, :users, column: :created_by_id
    add_foreign_key :specifications, :users, column: :updated_by_id
  end
end
