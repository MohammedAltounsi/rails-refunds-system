module RefundGateway
  # Ask Stripe to refund a charge. This does NOT settle anything in the
  # ledger — a refund can still fail or reverse after Stripe accepts it. The
  # ledger books the money only when the signature-verified webhook confirms
  # it (see Refund#settle!).
  def self.create(refund)
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
