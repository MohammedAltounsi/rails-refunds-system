class CreateCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :charges do |t|
      t.string :stripe_payment_intent_id, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "sar"

      t.timestamps
    end
    add_index :charges, :stripe_payment_intent_id, unique: true
  end
end
