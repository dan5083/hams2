class AddEachPriceToParts < ActiveRecord::Migration[8.0]
# In the generated migration file
  def change
    add_column :parts, :each_price, :decimal, precision: 10, scale: 2
  end
end
