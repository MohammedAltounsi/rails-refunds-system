# A refund's life: requested -> processing -> settled | failed. Money only
# ever leaves the ledger at `settled`, and only via a verified Stripe webhook
# (see app/controllers/webhooks/stripe_controller.rb) — never on request or
# on Stripe's synchronous create response, which can still be reversed.
class Refund < ApplicationRecord
  class InvalidTransition < StandardError; end
  class OverRefund < StandardError; end

  belongs_to :charge

  STATUSES = %w[requested processing settled failed].freeze
  TRANSITIONS = {
    "requested"  => %w[processing failed],
    "processing" => %w[settled failed],
    "settled"    => [],
    "failed"     => []
  }.freeze

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { greater_than: 0 }

  # The only way to create a refund. Locks the charge row so two concurrent
  # partial-refund requests can't both read "enough left" and together
  # over-refund it — the same time-of-check-to-time-of-use race project 1
  # guards against on a wallet spend. A retry with the same idempotency_key
  # returns the original refund instead of creating a second one.
  def self.request!(charge:, amount_cents:, idempotency_key:)
    return find_by!(idempotency_key: idempotency_key) if exists?(idempotency_key: idempotency_key)

    charge.with_lock do
      if charge.refundable_cents < amount_cents
        raise OverRefund, "refund of #{amount_cents} exceeds charge #{charge.id}'s remaining #{charge.refundable_cents}"
      end
      create!(charge: charge, amount_cents: amount_cents, idempotency_key: idempotency_key)
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(idempotency_key: idempotency_key)
  end

  # Stripe has accepted the refund request (still reversible on Stripe's side
  # until it settles).
  def mark_processing!(stripe_refund_id:)
    with_lock do
      transition_to!("processing")
      update!(stripe_refund_id: stripe_refund_id)
    end
  end

  # Settle on the verified `refund.updated` webhook: flip the status AND post
  # the balancing ledger reversal in the same locked transaction, keyed on
  # this refund, so a redelivered webhook reverses the money exactly once.
  def settle!
    with_lock do
      next if status == "settled"   # already settled by an earlier delivery
      transition_to!("settled")
      Ledger.post!(
        "refund #{id} for charge #{charge.stripe_payment_intent_id}",
        [ [ Ledger.account(Ledger::REVENUE_ACCOUNT), -amount_cents ],
         [ Ledger.account(Ledger::CASH_ACCOUNT), amount_cents ] ],
        key: "refund-settle:#{id}"
      )
    end
  end

  def fail!(reason)
    with_lock do
      transition_to!("failed")
      update!(failure_reason: reason.to_s.first(500))
    end
  end

  private

  def transition_to!(new_status)
    allowed = TRANSITIONS.fetch(status, [])
    raise InvalidTransition, "#{status} -> #{new_status} is not a legal refund transition" unless allowed.include?(new_status)
    update!(status: new_status)
  end
end
