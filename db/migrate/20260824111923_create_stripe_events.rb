class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "received"
      t.text :payload
      t.datetime :processed_at
      t.text :error

      t.timestamps
    end
    add_index :stripe_events, :event_id, unique: true
  end
end
