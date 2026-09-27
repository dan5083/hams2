# db/migrate/<timestamp>_add_home_sections_to_parts.rb
class AddHomeSectionsToParts < ActiveRecord::Migration[7.1]
  def change
    add_column :parts, :home_sections, :string, array: true, null: false, default: []
    add_index  :parts, :home_sections, using: :gin
  end
end
