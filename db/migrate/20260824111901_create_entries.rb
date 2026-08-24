class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries do |t|
      t.string :memo, null: false
      t.string :idempotency_key

      t.timestamps
    end
    add_index :entries, :idempotency_key, unique: true
  end
end
