class CreatePostings < ActiveRecord::Migration[8.1]
  def change
    create_table :postings do |t|
      t.references :entry, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :amount_cents, null: false

      t.timestamps
    end
  end
end
