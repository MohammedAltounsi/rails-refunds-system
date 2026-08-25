module RefundGateway
  # Ask Stripe to refund a charge. This does not settle anything in the
  # ledger; a refund can still fail or reverse after Stripe accepts it. The
  # ledger books the money only when the signature-verified webhook confirms
  # it (see Refund#settle!).
  def self.create(refund)
    # Demo seam: no Stripe account is wired on the public showcase, so stand in
    # for Stripe's "refund accepted" response and let the refund reach
    # `processing`. It still settles ONLY when the webhook is played (or a real
    # signed webhook arrives), never here. Off by default; the showcase opts in.
    if Rails.configuration.x.demo_mode
      return Struct.new(:id).new("re_demo_#{refund.idempotency_key}")
    end

    Stripe::Refund.create(
      {
        payment_intent: refund.charge.stripe_payment_intent_id,
        amount: refund.amount_cents,
        metadata: { refund_id: refund.id }
      },
      idempotency_key: "stripe-refund:#{refund.idempotency_key}"
    )
  end
end
