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

ActiveRecord::Schema[8.1].define(version: 2026_08_25_120200) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.datetime "created_at", null: false
    t.string "detail"
    t.integer "subject_id"
    t.string "subject_type"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject_type_and_subject_id"
  end

  create_table "charges", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "sar", null: false
    t.string "stripe_payment_intent_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_payment_intent_id"], name: "index_charges_on_stripe_payment_intent_id", unique: true
  end

  create_table "entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.string "memo", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_entries_on_idempotency_key", unique: true
  end

  create_table "payouts", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "sar", null: false
    t.string "failure_reason"
    t.string "idempotency_key", null: false
    t.string "payee", null: false
    t.string "status", default: "requested", null: false
    t.string "stripe_payout_id"
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_payouts_on_idempotency_key", unique: true
    t.index ["stripe_payout_id"], name: "index_payouts_on_stripe_payout_id", unique: true
  end

  create_table "postings", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.integer "entry_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_postings_on_account_id"
    t.index ["entry_id"], name: "index_postings_on_entry_id"
  end

  create_table "reconciliation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "global_sum_cents", default: 0, null: false
    t.boolean "invariants_ok", default: true, null: false
    t.integer "matched", default: 0, null: false
    t.integer "mismatched_count", default: 0, null: false
    t.integer "missing_count", default: 0, null: false
    t.integer "orphan_count", default: 0, null: false
    t.string "status", null: false
    t.integer "stripe_count", default: 0, null: false
    t.index ["created_at"], name: "index_reconciliation_runs_on_created_at"
  end

  create_table "refunds", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "charge_id", null: false
    t.datetime "created_at", null: false
    t.string "failure_reason"
    t.string "idempotency_key", null: false
    t.string "status", default: "requested", null: false
    t.string "stripe_refund_id"
    t.datetime "updated_at", null: false
    t.index ["charge_id"], name: "index_refunds_on_charge_id"
    t.index ["idempotency_key"], name: "index_refunds_on_idempotency_key", unique: true
    t.index ["stripe_refund_id"], name: "index_refunds_on_stripe_refund_id", unique: true
  end

  create_table "stripe_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.text "payload"
    t.datetime "processed_at"
    t.string "status", default: "received", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_stripe_events_on_event_id", unique: true
  end

  add_foreign_key "postings", "accounts"
  add_foreign_key "postings", "entries"
  add_foreign_key "refunds", "charges"
end
