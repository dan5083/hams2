class ClearLegacyNcrDocumentJsonb < ActiveRecord::Migration[7.2]
  def up
    # The backfill in CreateExternalNcrDocuments copied these into
    # external_ncr_documents but left the originals behind. Two references to
    # one Cloudinary file means removing the document row resurrects a dead
    # legacy card. No Cloudinary calls here — the files are still referenced.
    execute <<~SQL
      UPDATE external_ncrs
      SET ncr_data = ncr_data
        - 'cloudinary_public_id'
        - 'cloudinary_url'
        - 'original_filename'
        - 'file_size_bytes'
        - 'content_type'
        - 'document_uploaded_at'
      WHERE jsonb_exists_any(ncr_data, ARRAY[
        'cloudinary_public_id','cloudinary_url','original_filename',
        'file_size_bytes','content_type','document_uploaded_at'
      ]);
    SQL
  end

  def down
    # No-op — this data now lives in external_ncr_documents.
  end
end
