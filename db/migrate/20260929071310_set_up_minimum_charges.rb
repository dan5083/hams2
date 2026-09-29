# db/migrate/<timestamp>_set_up_minimum_charges.rb
#
# The minimum order charge is a fixed rule (£250 per customer order, £125
# when the order is chemical conversion only — see MinimumCharges). The only
# per-customer setting is the works-order minimum: nil = none; 75 for the
# customers who have been told the WO minimum is £75.
class SetUpMinimumCharges < ActiveRecord::Migration[8.0]
  def up
    add_column :organizations, :minimum_works_order_charge, :decimal, precision: 10, scale: 2

    # The two variable presets MinimumCharges attaches, looked up by name
    # (keep in step with MinimumCharges::PRESET_NAMES).
    ["Minimum order charge", "Minimum works order charge"].each do |name|
      execute <<~SQL
        INSERT INTO additional_charge_presets (id, name, is_variable, calculation_type, enabled, created_at, updated_at)
        SELECT gen_random_uuid(), '#{name}', TRUE, 'variable', TRUE, NOW(), NOW()
        WHERE NOT EXISTS (SELECT 1 FROM additional_charge_presets WHERE name = '#{name}')
      SQL
    end
  end

  def down
    remove_column :organizations, :minimum_works_order_charge
  end
end
