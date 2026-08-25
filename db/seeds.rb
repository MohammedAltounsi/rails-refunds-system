# Idempotent: Charge.capture! and Ledger.post! are both keyed, so re-running
# this (e.g. on every cold boot in production) never double-books.
charges = [
  { pi: "pi_seed_1", amount: 45_00 },
  { pi: "pi_seed_2", amount: 120_00 },
  { pi: "pi_seed_3", amount: 30_00 }
].map { |c| Charge.find_by(stripe_payment_intent_id: c[:pi]) || Charge.capture!(stripe_payment_intent_id: c[:pi], amount_cents: c[:amount]) }

# One fully settled partial refund, one still processing, one failed — enough
# to show every state on the refunds and ledger pages without hitting Stripe.
def seed_refund(charge, amount_cents, key, final_status:, stripe_id:)
  refund = Refund.request!(charge: charge, amount_cents: amount_cents, idempotency_key: key)
  return refund unless refund.status == "requested"

  refund.mark_processing!(stripe_refund_id: stripe_id)
  case final_status
  when "settled" then refund.settle!
  when "failed"  then refund.fail!("seed: card no longer accepts refunds")
  end
  refund
end

seed_refund(charges[0], 15_00, "seed-refund-1", final_status: "settled", stripe_id: "re_seed_1")
seed_refund(charges[1], 40_00, "seed-refund-2", final_status: nil,       stripe_id: "re_seed_2") # stays "processing"
seed_refund(charges[2], 30_00, "seed-refund-3", final_status: "failed",  stripe_id: "re_seed_3")

# One paid payout, one still processing, one failed — every payout state on the
# page without hitting Stripe. Idempotent: request!/pay! are keyed.
def seed_payout(payee, amount_cents, key, final_status:, stripe_id:)
  payout = Payout.request!(payee: payee, amount_cents: amount_cents, idempotency_key: key)
  return payout unless payout.status == "requested"

  payout.mark_processing!(stripe_payout_id: stripe_id)
  case final_status
  when "paid"   then payout.pay!
  when "failed" then payout.fail!("seed: destination bank rejected the transfer")
  end
  payout
end

seed_payout("Rahal Coffee",   80_00, "seed-payout-1", final_status: "paid",   stripe_id: "po_seed_1")
seed_payout("Najd Roasters",  45_00, "seed-payout-2", final_status: nil,      stripe_id: "po_seed_2") # stays "processing"
seed_payout("Hijazi Beans",   20_00, "seed-payout-3", final_status: "failed", stripe_id: "po_seed_3")

puts "Seeded #{Charge.count} charges, #{Refund.count} refunds, #{Payout.count} payouts."
