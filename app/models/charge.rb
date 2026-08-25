class Charge < ApplicationRecord
  has_many :refunds

  # A captured card payment enters the ledger the moment it exists here. This
  # app owns the outbound (refund) half of the money flow. It doesn't handle
  # inbound capture, so a Charge is created already-settled (see project 1 for
  # how a payment_intent.succeeded webhook actually captures one).
  def self.capture!(stripe_payment_intent_id:, amount_cents:, currency: "sar")
    charge = create!(
      stripe_payment_intent_id: stripe_payment_intent_id,
      amount_cents: amount_cents,
      currency: currency
    )
    Ledger.post!(
      "charge captured #{stripe_payment_intent_id}",
      [ [ Ledger.account(Ledger::CASH_ACCOUNT), -amount_cents ],
       [ Ledger.account(Ledger::REVENUE_ACCOUNT), amount_cents ] ],
      key: "charge-capture:#{stripe_payment_intent_id}"
    )
    charge
  end

  # Reserved = refunds not yet known to have failed. A `requested` or
  # `processing` refund holds its amount against the charge even before it
  # settles, so two concurrent refund requests can't both pass the "enough
  # left" check and together refund more than was captured.
  def refunded_cents
    refunds.where(status: %w[requested processing settled]).sum(:amount_cents)
  end

  def refundable_cents
    amount_cents - refunded_cents
  end
end
