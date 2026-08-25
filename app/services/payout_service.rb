# The one place that issues a payout. Accrues the liability (Payout.request!)
# and hands the payout to the processor.
#
# Real Stripe payouts need a Connect balance, which is out of scope for this
# showcase the same way the inbound capture is (see Charge; a captured payment
# is owned here as a fact). The disbursement is booked only when a verified
# `payout.paid` webhook confirms it, exactly like a refund settles.
module PayoutService
  def self.issue!(payee:, amount_cents:, idempotency_key:)
    payout = Payout.request!(payee: payee, amount_cents: amount_cents, idempotency_key: idempotency_key)
    return payout unless payout.status == "requested"   # idempotent replay of an in-flight/paid payout

    payout.mark_processing!(stripe_payout_id: "po_#{SecureRandom.hex(8)}")
    payout
  end
end
