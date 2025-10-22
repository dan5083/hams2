class ConvertDrawingFieldsToArrays < ActiveRecord::Migration[7.0]
  def up
    # Convert existing single values to arrays
    change_column :parts, :drawing_cloudinary_public_id, :string, array: true, default: [],
                  using: 'CASE WHEN drawing_cloudinary_public_id IS NULL THEN ARRAY[]::varchar[] ELSE ARRAY[drawing_cloudinary_public_id] END'

    change_column :parts, :drawing_filename, :string, array: true, default: [],
                  using: 'CASE WHEN drawing_filename IS NULL THEN ARRAY[]::varchar[] ELSE ARRAY[drawing_filename] END'

    # Optional: rename for clarity
    rename_column :parts, :drawing_cloudinary_public_id, :file_cloudinary_ids
    rename_column :parts, :drawing_filename, :file_filenames
  end

  def down
    # Take first element if reverting
    rename_column :parts, :file_cloudinary_ids, :drawing_cloudinary_public_id
    rename_column :parts, :file_filenames, :drawing_filename

    change_column :parts, :drawing_cloudinary_public_id, :string,
                  using: 'drawing_cloudinary_public_id[1]'
    change_column :parts, :drawing_filename, :string,
                  using: 'drawing_filename[1]'
  end
end
