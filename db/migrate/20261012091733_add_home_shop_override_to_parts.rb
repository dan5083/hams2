class AddHomeShopOverrideToParts < ActiveRecord::Migration[8.0]
  def change
    add_column :parts, :home_shop_override, :string
  end
end
