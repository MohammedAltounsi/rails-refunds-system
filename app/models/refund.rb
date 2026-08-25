# A refund's life: requested -> processing -> settled | failed. Money only
# ever leaves the ledger at `settled`, and only via a verified Stripe webhook
# (see app/controllers/webhooks/stripe_controller.rb). It never leaves on the
# request itself or on Stripe's synchronous create response, which can still
# be reversed.
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
  # over-refund it. Same time-of-check-to-time-of-use race project 1 guards
  # against on a wallet spend. A retry with the same idempotency_key returns
  # the original refund instead of creating a second one.
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

  # Strict settle, for the internal happy path (seed, and the FSM contract
  # tests): only a `processing` refund may settle. Flips the status AND posts
  # the balancing ledger reversal in the same locked transaction, keyed on this
  # refund, so a repeat is a no-op.
  def settle!
    with_lock do
      next if status == "settled"   # already settled by an earlier call
      transition_to!("settled")
      post_reversal!
    end
  end

  def fail!(reason)
    with_lock do
      transition_to!("failed")
      update!(failure_reason: reason.to_s.first(500))
    end
  end

  # --- Webhook boundary: convergent, ordering-tolerant --------------------
  #
  # Stripe delivers events at-least-once and out of order. The strict FSM above
  # is right for our own code, but wrong at the webhook edge: a `succeeded`
  # event can arrive before we recorded `processing`, or after a crash left the
  # row `failed`, and raising there would return 500 and make Stripe retry the
  # delivery indefinitely without ever booking money Stripe already moved. So
  # the webhook calls these instead.

  # A signature-verified Stripe "succeeded" is authoritative: the money left.
  # Converge to settled from ANY non-settled state and book the reversal exactly
  # once (Ledger.post! is keyed). Idempotent under redelivery.
  def apply_stripe_succeeded!(stripe_refund_id: nil)
    with_lock do
      self.stripe_refund_id ||= stripe_refund_id
      next if status == "settled"   # already booked by an earlier delivery
      # If this row was marked `failed` on an ambiguous Stripe error, Stripe now
      # confirms it actually succeeded. The over-refund CONSTRAINT TRIGGER is
      # the backstop if the reserve was reused in between.
      update!(status: "settled", failure_reason: nil)
      post_reversal!
    end
  end

  # A verified Stripe "failed". Never un-books a settled refund (a late/stale
  # failed after a succeed is ignored); otherwise records the failure once.
  def apply_stripe_failed!(reason)
    with_lock do
      next if status == "settled"   # money already booked; a stale failed is ignored
      next if status == "failed"
      update!(status: "failed", failure_reason: reason.to_s.first(500))
    end
  end

  private

  def post_reversal!
    Ledger.post!(
      "refund #{id} for charge #{charge.stripe_payment_intent_id}",
      [ [ Ledger.account(Ledger::REVENUE_ACCOUNT), -amount_cents ],
       [ Ledger.account(Ledger::CASH_ACCOUNT), amount_cents ] ],
      key: "refund-settle:#{id}"
    )
  end

  def transition_to!(new_status)
    allowed = TRANSITIONS.fetch(status, [])
    raise InvalidTransition, "#{status} -> #{new_status} is not a legal refund transition" unless allowed.include?(new_status)
    update!(status: new_status)
  end
end
