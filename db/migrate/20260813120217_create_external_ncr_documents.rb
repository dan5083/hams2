class CreateExternalNcrDocuments < ActiveRecord::Migration[7.2]
  def up
    create_table :external_ncr_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :external_ncr, type: :uuid, null: false, foreign_key: true
      t.references :uploaded_by,  type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string   :document_type, null: false, default: 'incoming_ncr'
      t.string   :cloudinary_public_id, null: false
      t.string   :cloudinary_url
      t.string   :original_filename
      t.bigint   :file_size_bytes
      t.string   :content_type
      t.text     :note
      t.datetime :uploaded_at, null: false
      t.timestamps
    end

    add_index :external_ncr_documents, [:external_ncr_id, :document_type]
    add_index :external_ncr_documents, :cloudinary_public_id, unique: true

    execute <<~SQL
      INSERT INTO external_ncr_documents
        (id, external_ncr_id, uploaded_by_id, document_type, cloudinary_public_id,
         cloudinary_url, original_filename, file_size_bytes, content_type,
         uploaded_at, created_at, updated_at)
      SELECT gen_random_uuid(), n.id, n.created_by_id, 'incoming_ncr',
             n.ncr_data->>'cloudinary_public_id',
             n.ncr_data->>'cloudinary_url',
             n.ncr_data->>'original_filename',
             NULLIF(n.ncr_data->>'file_size_bytes','')::bigint,
             n.ncr_data->>'content_type',
             COALESCE(NULLIF(n.ncr_data->>'document_uploaded_at','')::timestamptz, n.created_at),
             now(), now()
      FROM external_ncrs n
      WHERE COALESCE(n.ncr_data->>'cloudinary_public_id','') <> '';
    SQL
  end

  def down
    drop_table :external_ncr_documents
  end
end
