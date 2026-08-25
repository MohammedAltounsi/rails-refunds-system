# The one place that issues a refund. Ties together the app-level cap check
# (Refund.request!), the Stripe API call, and the transition into "processing",
# or straight to "failed" if Stripe rejects the request synchronously.
module RefundService
  def self.issue!(charge:, amount_cents:, idempotency_key:)
    refund = Refund.request!(charge: charge, amount_cents: amount_cents, idempotency_key: idempotency_key)
    return refund unless refund.status == "requested"   # idempotent replay of an in-flight/settled refund

    begin
      stripe_refund = RefundGateway.create(refund)
      refund.mark_processing!(stripe_refund_id: stripe_refund.id)
    rescue Stripe::StripeError => e
      refund.fail!("stripe: #{e.message}")
    end
    refund
  end
end
