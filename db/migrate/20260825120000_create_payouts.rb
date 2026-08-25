class CreatePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.string  :payee, null: false
      t.integer :amount_cents, null: false
      t.string  :currency, null: false, default: "sar"
      t.string  :status, null: false, default: "requested"
      t.string  :idempotency_key, null: false
      t.string  :stripe_payout_id
      t.string  :failure_reason
      t.timestamps
    end

    add_index :payouts, :idempotency_key, unique: true
    add_index :payouts, :stripe_payout_id, unique: true
  end
end
