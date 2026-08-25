class Account < ApplicationRecord
  has_many :postings

  # A balance is never stored. It's derived by summing the account's postings.
  # A stored balance drifts out of sync; summing an append-only log doesn't.
  def balance_cents
    postings.sum(:amount_cents)
  end
end
