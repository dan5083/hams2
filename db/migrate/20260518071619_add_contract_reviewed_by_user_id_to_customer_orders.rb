class AddContractReviewedByUserIdToCustomerOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_orders, :contract_reviewed_by_user_id, :uuid, null: true, default: nil

    add_index :customer_orders, :contract_reviewed_by_user_id

    add_foreign_key :customer_orders, :users,
                    column: :contract_reviewed_by_user_id,
                    on_delete: :nullify
  end
end
