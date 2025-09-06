# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_06_123327) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "additional_charge_presets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.decimal "amount", precision: 10, scale: 2
    t.boolean "is_variable", default: false, null: false
    t.string "calculation_type"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_additional_charge_presets_on_enabled"
    t.index ["is_variable"], name: "index_additional_charge_presets_on_is_variable"
    t.index ["name"], name: "index_additional_charge_presets_on_name", unique: true
  end

  create_table "customer_orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.string "number", null: false
    t.date "date_received", null: false
    t.boolean "voided", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_customer_orders_on_customer_id"
    t.index ["date_received"], name: "index_customer_orders_on_date_received"
    t.index ["number"], name: "index_customer_orders_on_number"
    t.index ["voided"], name: "index_customer_orders_on_voided"
  end

  create_table "invoice_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "release_note_id"
    t.string "kind", null: false
    t.integer "quantity", null: false
    t.text "description", null: false
    t.decimal "line_amount_ex_tax", precision: 10, scale: 2, null: false
    t.decimal "line_amount_tax", precision: 10, scale: 2, null: false
    t.decimal "line_amount_inc_tax", precision: 10, scale: 2, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "position"], name: "index_invoice_items_on_invoice_id_and_position"
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
    t.index ["kind"], name: "index_invoice_items_on_kind"
    t.index ["release_note_id"], name: "index_invoice_items_on_release_note_id"
    t.check_constraint "line_amount_ex_tax >= 0::numeric AND line_amount_tax >= 0::numeric AND line_amount_inc_tax >= 0::numeric", name: "check_positive_amounts"
    t.check_constraint "quantity > 0", name: "check_positive_quantity"
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.date "date", default: -> { "CURRENT_DATE" }, null: false
    t.decimal "total_ex_tax", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_tax", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total_inc_tax", precision: 10, scale: 2, default: "0.0", null: false
    t.string "xero_tax_type", null: false
    t.decimal "tax_rate_pct", precision: 5, scale: 2, null: false
    t.string "xero_id"
    t.string "number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["date"], name: "index_invoices_on_date"
    t.index ["number"], name: "index_invoices_on_number", unique: true, where: "(number IS NOT NULL)"
    t.index ["xero_id"], name: "index_invoices_on_xero_id", unique: true, where: "(xero_id IS NOT NULL)"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.boolean "enabled"
    t.boolean "is_customer"
    t.boolean "is_supplier"
    t.uuid "xero_contact_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["xero_contact_id"], name: "index_organizations_on_xero_contact_id"
  end

  create_table "parts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.string "uniform_part_number", null: false
    t.string "uniform_part_issue", default: "A", null: false
    t.string "description"
    t.string "material"
    t.text "specification"
    t.text "notes"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "special_instructions"
    t.string "process_type"
    t.jsonb "customisation_data", default: {}
    t.uuid "replaces_id"
    t.text "specified_thicknesses"
    t.index ["customer_id", "enabled"], name: "index_parts_on_customer_id_and_enabled"
    t.index ["customer_id", "uniform_part_number", "uniform_part_issue"], name: "index_parts_on_customer_and_part_number_and_issue", unique: true
    t.index ["customer_id"], name: "index_parts_on_customer_id"
    t.index ["customisation_data"], name: "index_parts_on_customisation_data", using: :gin
    t.index ["enabled"], name: "index_parts_on_enabled"
    t.index ["process_type"], name: "index_parts_on_process_type"
    t.index ["replaces_id"], name: "index_parts_on_replaces_id"
    t.index ["uniform_part_number"], name: "index_parts_on_uniform_part_number"
  end

  create_table "release_levels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "statement", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_release_levels_on_enabled"
    t.index ["name"], name: "index_release_levels_on_name", unique: true
  end

  create_table "release_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "number", null: false
    t.uuid "works_order_id", null: false
    t.uuid "issued_by_id", null: false
    t.date "date", null: false
    t.integer "quantity_accepted", default: 0, null: false
    t.integer "quantity_rejected", default: 0, null: false
    t.text "remarks"
    t.boolean "no_invoice", default: false, null: false
    t.boolean "voided", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "measured_thicknesses"
    t.index ["date"], name: "index_release_notes_on_date"
    t.index ["issued_by_id"], name: "index_release_notes_on_issued_by_id"
    t.index ["no_invoice"], name: "index_release_notes_on_no_invoice"
    t.index ["number"], name: "index_release_notes_on_number", unique: true
    t.index ["voided"], name: "index_release_notes_on_voided"
    t.index ["works_order_id"], name: "index_release_notes_on_works_order_id"
    t.check_constraint "quantity_accepted > 0 OR quantity_rejected > 0", name: "check_has_quantity"
    t.check_constraint "quantity_accepted >= 0 AND quantity_rejected >= 0", name: "check_positive_quantities"
  end

  create_table "sequences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_sequences_on_key", unique: true
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "specification_presets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "content", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_specification_presets_on_enabled"
    t.index ["name"], name: "index_specification_presets_on_name", unique: true
  end

  create_table "transport_methods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_transport_methods_on_enabled"
    t.index ["name"], name: "index_transport_methods_on_name", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest"
    t.string "username"
    t.string "full_name"
    t.boolean "enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "magic_link_token"
    t.datetime "magic_link_expires_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["magic_link_expires_at"], name: "index_users_on_magic_link_expires_at"
    t.index ["magic_link_token"], name: "index_users_on_magic_link_token", unique: true, where: "(magic_link_token IS NOT NULL)"
  end

  create_table "works_orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "number", null: false
    t.uuid "customer_order_id", null: false
    t.uuid "part_id", null: false
    t.uuid "release_level_id", null: false
    t.uuid "transport_method_id", null: false
    t.string "customer_order_line"
    t.string "part_number", null: false
    t.string "part_issue", null: false
    t.string "part_description", null: false
    t.integer "quantity", null: false
    t.integer "quantity_released", default: 0, null: false
    t.boolean "is_open", default: true, null: false
    t.boolean "voided", default: false, null: false
    t.decimal "lot_price", precision: 10, scale: 2, null: false
    t.string "price_type", null: false
    t.decimal "each_price", precision: 10, scale: 2
    t.string "material"
    t.string "batch"
    t.jsonb "customised_process_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "additional_charge_data", default: {}
    t.index ["additional_charge_data"], name: "index_works_orders_on_additional_charge_data", using: :gin
    t.index ["customer_order_id"], name: "index_works_orders_on_customer_order_id"
    t.index ["is_open"], name: "index_works_orders_on_is_open"
    t.index ["number"], name: "index_works_orders_on_number", unique: true
    t.index ["part_id"], name: "index_works_orders_on_part_id"
    t.index ["part_number", "part_issue"], name: "index_works_orders_on_part_number_and_part_issue"
    t.index ["release_level_id"], name: "index_works_orders_on_release_level_id"
    t.index ["transport_method_id"], name: "index_works_orders_on_transport_method_id"
    t.index ["voided"], name: "index_works_orders_on_voided"
    t.check_constraint "lot_price >= 0::numeric AND (each_price IS NULL OR each_price >= 0::numeric)", name: "check_positive_prices"
    t.check_constraint "quantity > 0 AND quantity_released >= 0 AND quantity_released <= quantity", name: "check_positive_quantities"
  end

  create_table "xero_contacts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "contact_status"
    t.boolean "is_customer"
    t.boolean "is_supplier"
    t.string "merged_to_contact_id"
    t.string "accounts_receivable_tax_type"
    t.string "accounts_payable_tax_type"
    t.string "xero_id"
    t.jsonb "xero_data"
    t.datetime "last_synced_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "customer_orders", "organizations", column: "customer_id"
  add_foreign_key "invoice_items", "invoices"
  add_foreign_key "invoice_items", "release_notes"
  add_foreign_key "invoices", "organizations", column: "customer_id"
  add_foreign_key "organizations", "xero_contacts"
  add_foreign_key "parts", "organizations", column: "customer_id"
  add_foreign_key "parts", "parts", column: "replaces_id"
  add_foreign_key "release_notes", "users", column: "issued_by_id"
  add_foreign_key "release_notes", "works_orders"
  add_foreign_key "sessions", "users"
  add_foreign_key "works_orders", "customer_orders"
  add_foreign_key "works_orders", "parts"
  add_foreign_key "works_orders", "release_levels"
  add_foreign_key "works_orders", "transport_methods"
end
