class CreateWorksOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :works_orders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Sequential number for works orders
      t.integer :number, null: false

      # Links to other entities
      t.references :customer_order, null: false, foreign_key: true, type: :uuid
      t.references :part, null: false, foreign_key: true, type: :uuid
      t.references :part_processing_instruction, null: false, foreign_key: true, type: :uuid,
                   index: { name: 'index_works_orders_on_ppi_id' }
      t.references :release_level, null: false, foreign_key: true, type: :uuid
      t.references :transport_method, null: false, foreign_key: true, type: :uuid

      # Customer order details
      t.string :customer_order_line # Line number on customer's PO

      # Part details (cached for performance/historical record)
      t.string :part_number, null: false
      t.string :part_issue, null: false
      t.string :part_description, null: false

      # Work details
      t.integer :quantity, null: false
      t.integer :quantity_released, null: false, default: 0
      t.date :due_date, null: false

      # Status
      t.boolean :is_open, null: false, default: true
      t.boolean :voided, null: false, default: false

      # Pricing
      t.decimal :lot_price, precision: 10, scale: 2, null: false
      t.string :price_type, null: false # 'lot', 'each'
      t.decimal :each_price, precision: 10, scale: 2, null: true

      # Materials/batch info
      t.string :material
      t.string :batch

      # Customized process data for this specific work order
      t.jsonb :customised_process_data, default: {}

      t.timestamps
    end

    add_index :works_orders, :number, unique: true
    add_index :works_orders, :due_date
    add_index :works_orders, :is_open
    add_index :works_orders, :voided
    add_index :works_orders, [:part_number, :part_issue]

    # Constraints
    execute <<-SQL
      ALTER TABLE works_orders
      ADD CONSTRAINT check_positive_quantities
      CHECK (quantity > 0 AND quantity_released >= 0 AND quantity_released <= quantity);
    SQL

    execute <<-SQL
      ALTER TABLE works_orders
      ADD CONSTRAINT check_positive_prices
      CHECK (lot_price >= 0 AND (each_price IS NULL OR each_price >= 0));
    SQL
  end
end
