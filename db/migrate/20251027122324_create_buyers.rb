class CreateBuyers < ActiveRecord::Migration[8.0]
  def change
    create_table :buyers, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :email, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :buyers, [:organization_id, :email], unique: true
    add_index :buyers, :enabled
  end
end
