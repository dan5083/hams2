class RemoveRequestedDeliveryDateFromCustomerOrdersAndDueDateFromWorksOrders < ActiveRecord::Migration[8.0]
  def change
    remove_column :customer_orders, :requested_delivery_date, :date
    remove_column :works_orders, :due_date, :date
  end
end
