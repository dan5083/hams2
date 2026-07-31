class DropContractReviewFromCustomerOrders < ActiveRecord::Migration[8.0]
  def up
    # Column exists in production but predates schema.rb (added without a
    # migration); guard everything so this runs cleanly on both.
    return unless column_exists?(:customer_orders, :contract_reviewed_by_user_id)

    if index_exists?(:customer_orders, :contract_reviewed_by_user_id)
      remove_index :customer_orders, :contract_reviewed_by_user_id
    end
    if foreign_key_exists?(:customer_orders, column: :contract_reviewed_by_user_id)
      remove_foreign_key :customer_orders, column: :contract_reviewed_by_user_id
    end
    remove_column :customer_orders, :contract_reviewed_by_user_id
  end

  def down
    add_column :customer_orders, :contract_reviewed_by_user_id, :uuid unless column_exists?(:customer_orders, :contract_reviewed_by_user_id)
  end
end
