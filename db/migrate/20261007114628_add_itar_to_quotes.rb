# db/migrate/20261007120000_add_itar_to_quotes.rb
#
# ITAR / export-controlled quotes: the drawings still go to Cloudinary and
# onto the part as normal, but they must not be sent to the assistant.
# drawing_description is the reviewer's own words standing in for them.
class AddItarToQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :quotes, :itar, :boolean, default: false, null: false
    add_column :quotes, :drawing_description, :text
  end
end
