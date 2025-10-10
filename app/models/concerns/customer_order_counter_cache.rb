# app/models/concerns/customer_order_counter_cache.rb
# NEW FILE - Shared concern for updating customer_order cached counts
module CustomerOrderCounterCache
  extend ActiveSupport::Concern

  private

  def update_customer_order_counts
    return unless customer_order_id_previously_was || customer_order_id

    # Update old customer order if it changed
    update_counts_for_customer_order_id(customer_order_id_previously_was) if customer_order_id_previously_was

    # Update new customer order
    update_counts_for_customer_order_id(customer_order_id) if customer_order_id
  end

  def update_counts_for_customer_order_id(co_id)
    return unless co_id

    CustomerOrder.where(id: co_id).update_all(
      open_works_orders_count: WorksOrder.where(customer_order_id: co_id, voided: false, is_open: true).count,
      fully_released_works_orders_count: WorksOrder.where(customer_order_id: co_id, voided: false, is_open: true, is_fully_released: true).count,
      uninvoiced_accepted_quantity: ReleaseNote.joins(:works_order)
        .left_joins(:invoice_item)
        .where(works_orders: { customer_order_id: co_id })
        .where(invoice_items: { id: nil })
        .where(voided: false, no_invoice: false)
        .where('release_notes.quantity_accepted > 0')
        .sum(:quantity_accepted)
    )
  end
end
