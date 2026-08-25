class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string  :actor, null: false          # who did it (Basic-auth user, or "demo")
      t.string  :action, null: false         # e.g. "refund.issue", "payout.issue"
      t.string  :subject_type
      t.integer :subject_id
      t.string  :detail
      t.datetime :created_at, null: false
    end

    add_index :audit_logs, :created_at
    add_index :audit_logs, [ :subject_type, :subject_id ]
  end
end
