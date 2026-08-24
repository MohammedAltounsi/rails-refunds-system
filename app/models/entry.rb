class Entry < ApplicationRecord
  has_many :postings, dependent: :destroy

  # THE rule of double-entry: the postings in an entry must sum to zero. Money
  # is only ever MOVED, never created or destroyed. If this fails, save!
  # raises and the whole entry is rolled back — no half-written money.
  validate :must_balance

  private

  def must_balance
    return if postings.sum(&:amount_cents).zero?
    errors.add(:base, "entry does not balance — postings must sum to zero")
  end
end
