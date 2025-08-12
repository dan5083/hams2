class CreateCustomerOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :customer_orders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Link to customer
      t.references :customer, null: false, foreign_key: { to_table: :organizations }, type: :uuid

      # Order details
      t.string :number, null: false # Customer's PO number
      t.date :date_received, null: false
      t.date :requested_delivery_date

      # Status
      t.boolean :voided, null: false, default: false
      t.text :notes

      t.timestamps
    end

    add_index :customer_orders, :number
    add_index :customer_orders, :date_received
    add_index :customer_orders, :voided
  end
end
