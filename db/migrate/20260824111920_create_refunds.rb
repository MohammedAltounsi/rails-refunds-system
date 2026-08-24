class CreateRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :refunds do |t|
      t.references :charge, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "requested"
      t.string :idempotency_key, null: false
      t.string :stripe_refund_id
      t.string :failure_reason

      t.timestamps
    end
    add_index :refunds, :idempotency_key, unique: true
    add_index :refunds, :stripe_refund_id, unique: true
  end
end
