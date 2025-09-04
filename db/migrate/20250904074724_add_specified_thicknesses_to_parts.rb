class AddSpecifiedThicknessesToParts < ActiveRecord::Migration[8.0]
  def change
    add_column :parts, :specified_thicknesses, :text
  end
end
