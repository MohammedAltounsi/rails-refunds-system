class Account < ApplicationRecord
  has_many :postings

  # A balance is NEVER stored. It's derived by summing the account's postings.
  # Stored balances drift and lie; a sum of an append-only log can't.
  def balance_cents
    postings.sum(:amount_cents)
  end
end
