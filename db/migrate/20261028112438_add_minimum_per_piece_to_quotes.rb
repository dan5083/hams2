class AddMinimumPerPieceToQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :quotes, :minimum_per_piece, :decimal, precision: 8, scale: 2, default: 1.50, null: false
    add_column :quotes, :edited_at, :datetime
  end
end
