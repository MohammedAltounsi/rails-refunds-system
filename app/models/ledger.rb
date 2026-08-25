module Ledger
  # Named system accounts, so a typo can't silently open a second account.
  CASH_ACCOUNT    = "stripe:cash"           # external money moving through Stripe (an asset source)
  REVENUE_ACCOUNT = "revenue:charges"       # captured revenue that a refund gives back
  PAYABLE_ACCOUNT = "liability:payouts"     # money owed to a payee, accrued then disbursed
  EXPENSE_ACCOUNT = "expense:payouts"       # the cost recognised when a payout is accrued

  def self.account(name)
    Account.find_or_create_by!(name: name)
  end

  # The only way money moves. Give it a memo and the lines that move.
  # lines = [[account, amount_cents], ...]; amounts must sum to zero.
  #
  # key: an idempotency key. Pass the same key twice (a retry, a webhook
  # redelivery) and the money moves once. The first entry is returned again
  # instead of a duplicate being created. This is what makes a refund
  # reversal safe to replay: settling the same refund twice books it once.
  #
  # Everything happens inside one DB transaction: either every posting lands,
  # or none do. Balance is enforced twice: in Ruby by Entry#must_balance on
  # every save, and in Postgres by a deferred CONSTRAINT TRIGGER
  # (lib/tasks/db_constraints.rake) that rejects any unbalanced entry at
  # COMMIT, even if the app layer has a bug.
  def self.post!(memo, lines, key: nil)
    if key && (existing = Entry.find_by(idempotency_key: key))
      return existing
    end

    Entry.transaction do
      entry = Entry.new(memo: memo, idempotency_key: key)
      lines.each { |account, cents| entry.postings.build(account: account, amount_cents: cents) }
      entry.save!
      entry
    end
  rescue ActiveRecord::RecordNotUnique
    # Race: another request posted the same key between our check and our
    # save. The unique index caught it and rolled us back. The winner
    # already exists. Return it. Money still moved exactly once.
    Entry.find_by!(idempotency_key: key)
  end
end
