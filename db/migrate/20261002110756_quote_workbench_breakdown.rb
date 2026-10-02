# db/migrate/20261002120000_quote_workbench_breakdown.rb
#
# Quote workbench changes, 2 Oct 2026:
#   - quotes.customer_id may be NULL while the assistant is identifying the
#     customer from the enquiry (status proposing/proposed/proposal_failed);
#     Quote validates its presence from draft onwards.
#   - quote_items.breakdown: the per-treatment make-up of unit_amount,
#     [{ "description", "unit_amount" }], saved from the proposal line's
#     components. Shown with prices to the quoter, without to the customer.
class QuoteWorkbenchBreakdown < ActiveRecord::Migration[7.1]
  def up
    change_column_null :quotes, :customer_id, true
    add_column :quote_items, :breakdown, :jsonb, null: false, default: []
  end

  def down
    remove_column :quote_items, :breakdown
    change_column_null :quotes, :customer_id, false
  end
end
