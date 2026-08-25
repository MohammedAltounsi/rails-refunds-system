# Dispatches a verified Stripe event to the right convergent handler. Extracted
# from the webhook controller so the exact same logic runs in two places:
#
#   - inline, on the webhook request (the happy path; Stripe retries on a 500)
#   - from the recovery sweep (ReprocessStuckStripeEventsJob), which re-runs any
#     inbox event that never reached `processed`, recovering a settlement that
#     was dropped by a crash between recording the event and booking the money.
#
# Every handler is convergent and idempotent (keyed ledger postings), so running
# an event twice books money exactly once.
module StripeEventProcessor
  def self.process(event)
    case event.type
    when "refund.updated" then refund_updated(event.data.object)
    when "refund.failed"  then refund_failed(event.data.object)
    when "payout.paid"    then payout_paid(event.data.object)
    when "payout.failed"  then payout_failed(event.data.object)
    end
  end

  # Rebuild a Stripe event object from the raw payload we stored in the inbox,
  # so the sweep can reprocess without the original request.
  def self.from_payload(payload)
    Stripe::Event.construct_from(JSON.parse(payload))
  end

  def self.refund_updated(stripe_refund)
    refund = find_refund(stripe_refund)
    return unless refund

    case stripe_refund.status
    when "succeeded" then refund.apply_stripe_succeeded!(stripe_refund_id: stripe_refund.id)
    when "failed"    then refund.apply_stripe_failed!("stripe: #{stripe_refund.failure_reason}")
    end
  end

  def self.refund_failed(stripe_refund)
    find_refund(stripe_refund)&.apply_stripe_failed!("stripe: #{stripe_refund.failure_reason}")
  end

  def self.payout_paid(stripe_payout)
    find_payout(stripe_payout)&.apply_stripe_paid!(stripe_payout_id: stripe_payout.id)
  end

  def self.payout_failed(stripe_payout)
    reason = stripe_payout.try(:failure_message) || stripe_payout.try(:failure_reason)
    find_payout(stripe_payout)&.apply_stripe_failed!("stripe: #{reason}")
  end

  def self.find_refund(stripe_refund)
    Refund.find_by(id: stripe_refund.metadata["refund_id"]) ||
      Refund.find_by(stripe_refund_id: stripe_refund.id)
  end

  def self.find_payout(stripe_payout)
    Payout.find_by(id: stripe_payout.metadata["payout_id"]) ||
      Payout.find_by(stripe_payout_id: stripe_payout.id)
  end
end
