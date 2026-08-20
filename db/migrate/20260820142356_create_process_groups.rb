# db/migrate/XXXXXXXXXXXXXX_create_process_groups.rb
# Generated with: rails g migration CreateProcessGroups
# (paste this body over the generated file; the generator stamps the
# correct Migration[x.y] version for the app)
class CreateProcessGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :process_groups do |t|
      t.string :number, null: false
      t.string :process_fingerprint, null: false
      t.bigint :lead_works_order_id
      t.timestamps
    end
    add_index :process_groups, :number, unique: true
    add_index :process_groups, :lead_works_order_id

    add_reference :works_orders, :process_group, index: true
  end
end
