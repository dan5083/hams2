class MakeHalNcrNumberNullable < ActiveRecord::Migration[8.0]
  def change
    change_column_null :external_ncrs, :hal_ncr_number, true
  end
end
