# db/migrate/<timestamp>_create_promises.rb
class CreatePromises < ActiveRecord::Migration[7.1]
  def change
    create_table :promises, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :works_order, type: :uuid, null: false, foreign_key: true, index: true
      t.integer    :quantity, null: false
      t.date       :due_on,   null: false
      t.string     :note
      t.references :promised_by,  type: :uuid, foreign_key: { to_table: :users }, index: false
      t.datetime   :cancelled_at
      t.references :cancelled_by, type: :uuid, foreign_key: { to_table: :users }, index: false
      t.timestamps
    end
    add_index :promises, [:due_on, :cancelled_at]
    add_check_constraint :promises, "quantity > 0", name: "check_promise_quantity_positive"

    # Section heads land on their board instead of the dashboard. A
    # ShopSectionBoard::SECTIONS key, or NULL for everyone else.
    add_column :users, :home_section, :string
  end
end
