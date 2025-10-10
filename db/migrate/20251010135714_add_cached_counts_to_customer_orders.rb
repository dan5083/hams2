# db/migrate/20251010140000_add_cached_counts_to_customer_orders.rb
class AddCachedCountsToCustomerOrders < ActiveRecord::Migration[8.0]
  def up
    # Add cached columns to customer_orders
    add_column :customer_orders, :open_works_orders_count, :integer, default: 0, null: false
    add_column :customer_orders, :fully_released_works_orders_count, :integer, default: 0, null: false
    add_column :customer_orders, :uninvoiced_accepted_quantity, :integer, default: 0, null: false

    # Add index for efficient sorting and filtering
    add_index :customer_orders, [:open_works_orders_count, :fully_released_works_orders_count, :uninvoiced_accepted_quantity],
              name: 'index_customer_orders_on_cached_invoice_status'

    # Add cached boolean to works_orders
    add_column :works_orders, :is_fully_released, :boolean, default: false, null: false
    add_index :works_orders, :is_fully_released

    # Backfill existing data
    say_with_time "Backfilling works_orders.is_fully_released" do
      execute <<-SQL
        UPDATE works_orders
        SET is_fully_released = (quantity_released >= quantity)
        WHERE voided = false
      SQL
    end

    say_with_time "Backfilling customer_orders counts" do
      execute <<-SQL
        UPDATE customer_orders
        SET
          open_works_orders_count = (
            SELECT COUNT(*)
            FROM works_orders
            WHERE works_orders.customer_order_id = customer_orders.id
              AND works_orders.voided = false
              AND works_orders.is_open = true
          ),
          fully_released_works_orders_count = (
            SELECT COUNT(*)
            FROM works_orders
            WHERE works_orders.customer_order_id = customer_orders.id
              AND works_orders.voided = false
              AND works_orders.is_open = true
              AND works_orders.is_fully_released = true
          ),
          uninvoiced_accepted_quantity = (
            SELECT COALESCE(SUM(rn.quantity_accepted), 0)
            FROM works_orders wo
            INNER JOIN release_notes rn ON rn.works_order_id = wo.id
            LEFT JOIN invoice_items ii ON ii.release_note_id = rn.id
            WHERE wo.customer_order_id = customer_orders.id
              AND wo.voided = false
              AND rn.voided = false
              AND rn.no_invoice = false
              AND rn.quantity_accepted > 0
              AND ii.id IS NULL
          )
      SQL
    end
  end

  def down
    remove_index :customer_orders, name: 'index_customer_orders_on_cached_invoice_status'
    remove_column :customer_orders, :open_works_orders_count
    remove_column :customer_orders, :fully_released_works_orders_count
    remove_column :customer_orders, :uninvoiced_accepted_quantity

    remove_index :works_orders, :is_fully_released
    remove_column :works_orders, :is_fully_released
  end
end
