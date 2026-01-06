class RemoveSpecNumberFromSpecifications < ActiveRecord::Migration[8.0]
  def change
    remove_index :specifications, :spec_number
    remove_column :specifications, :spec_number, :string
  end
end
