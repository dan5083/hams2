class FixProcessGroupLeadColumnType < ActiveRecord::Migration[7.1]
  def up
    remove_index  :process_groups, :lead_works_order_id
    remove_column :process_groups, :lead_works_order_id
    add_column    :process_groups, :lead_works_order_id, :uuid
    add_index     :process_groups, :lead_works_order_id
  end

  def down
    remove_index  :process_groups, :lead_works_order_id
    remove_column :process_groups, :lead_works_order_id
    add_column    :process_groups, :lead_works_order_id, :bigint
    add_index     :process_groups, :lead_works_order_id
  end
end
