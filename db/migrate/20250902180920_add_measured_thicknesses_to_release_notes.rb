class AddMeasuredThicknessesToReleaseNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :release_notes, :measured_thicknesses, :jsonb
  end
end
