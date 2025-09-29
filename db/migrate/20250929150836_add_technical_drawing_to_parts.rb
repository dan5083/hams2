# db/migrate/[timestamp]_add_technical_drawing_to_parts.rb
class AddTechnicalDrawingToParts < ActiveRecord::Migration[8.0]
  def change
    add_column :parts, :drawing_cloudinary_public_id, :string
    add_column :parts, :drawing_filename, :string

    add_index :parts, :drawing_cloudinary_public_id
  end
end
