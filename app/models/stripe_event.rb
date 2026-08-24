# The webhook inbox. Every Stripe event is recorded here exactly once (unique
# event_id), so a redelivery of an already-processed event is a no-op, and a
# processing failure is recorded and safe to reprocess on Stripe's next retry.
class StripeEvent < ApplicationRecord
  STATUSES = %w[received processed failed].freeze

  validates :event_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  # No uniqueness validation: it has a check-then-insert race and would raise
  # RecordInvalid before the DB is consulted. The unique index is the real
  # guard, caught in .record below — same idempotency pattern as Ledger.post!.

  scope :failed, -> { where(status: "failed") }

  def self.record(event, payload)
    create!(event_id: event.id, event_type: event.type, payload: payload)
  rescue ActiveRecord::RecordNotUnique
    find_by!(event_id: event.id)
  end

  def processed?
    status == "processed"
  end

  def mark_processed!
    update!(status: "processed", processed_at: Time.current, error: nil)
  end

  def mark_failed!(message)
    update!(status: "failed", error: message.to_s.first(500))
  end
end
