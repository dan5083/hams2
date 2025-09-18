# db/migrate/20250918000001_create_external_ncrs.rb
class CreateExternalNcrs < ActiveRecord::Migration[8.0]
  def change
    create_table :external_ncrs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Core identification
      t.integer :hal_ncr_number, null: false
      t.uuid :works_order_id, null: false
      t.date :date, null: false, default: -> { "CURRENT_DATE" }

      # Status and workflow
      t.string :status, null: false, default: 'draft'
      t.uuid :created_by_id, null: false
      t.uuid :assigned_to_id

      # NCR-specific data that can't be derived from works order
      t.jsonb :ncr_data, null: false, default: {}

      # Audit fields
      t.timestamps null: false

      # Indexes
      t.index :hal_ncr_number, unique: true
      t.index :works_order_id
      t.index :date
      t.index :status
      t.index :created_by_id
      t.index :assigned_to_id
      t.index :ncr_data, using: :gin
    end

    # Foreign key constraints
    add_foreign_key :external_ncrs, :works_orders
    add_foreign_key :external_ncrs, :users, column: :created_by_id
    add_foreign_key :external_ncrs, :users, column: :assigned_to_id

    # Check constraints
    add_check_constraint :external_ncrs,
      "status IN ('draft', 'in_progress', 'completed')",
      name: 'check_valid_status'

    add_check_constraint :external_ncrs,
      "hal_ncr_number > 0",
      name: 'check_positive_ncr_number'

    # Create sequence for HAL NCR numbers
    create_table :sequences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :key, null: false
      t.integer :value, null: false, default: 1
      t.timestamps null: false

      t.index :key, unique: true
    end unless table_exists?(:sequences)

    # Initialize the NCR sequence if it doesn't exist
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO sequences (key, value, created_at, updated_at)
          SELECT 'external_ncr_number', 1, NOW(), NOW()
          WHERE NOT EXISTS (SELECT 1 FROM sequences WHERE key = 'external_ncr_number')
        SQL
      end
    end
  end
end
