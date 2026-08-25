class Entry < ApplicationRecord
  has_many :postings, dependent: :destroy

  # The rule of double-entry: the postings in an entry must sum to zero. Money
  # is only ever moved, never created or destroyed. If this fails, save! raises
  # and the whole entry is rolled back, so no partial money is written.
  validate :must_balance

  private

  def must_balance
    return if postings.sum(&:amount_cents).zero?
    errors.add(:base, "entry does not balance, postings must sum to zero")
  end
end
