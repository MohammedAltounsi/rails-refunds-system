require "test_helper"

# Reconciliation is the safety net a payments team gets paged for, so it needs
# its own test. Stripe is injected (no network): run(stripe:) takes a
# controlled list, while the ledger side is read for real from settled
# refunds, built exactly as the webhook books them.
class ReconciliationServiceTest < ActiveSupport::TestCase
  def settle(stripe_refund_id, amount_cents, charge_amount: amount_cents)
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: charge_amount)
    refund = Refund.request!(charge: charge, amount_cents: amount_cents, idempotency_key: "recon-#{stripe_refund_id}")
    refund.mark_processing!(stripe_refund_id: stripe_refund_id)
    refund.settle!
    refund
  end

  test "a ledger that matches Stripe reconciles clean" do
    settle("re_a", 50_00)
    settle("re_b", 22_00)

    result = ReconciliationService.run(stripe: {
      "re_a" => { amount: 50_00 },
      "re_b" => { amount: 22_00 }
    })

    assert_equal 2, result.matched
    assert_empty result.missing
    assert_empty result.mismatched
    assert_empty result.orphans
    assert_empty result.unbalanced_entries
    assert_equal 0, result.global_sum_cents
    assert result.ok?, "a matching ledger should reconcile"
  end

  test "it flags a dropped webhook, a wrong amount, and an orphan reversal" do
    settle("re_match",  50_00)             # correct, in both
    settle("re_wrong",  40_00, charge_amount: 100_00) # ledger settled 40, Stripe says it refunded 50
    settle("re_orphan", 30_00)             # settled in the ledger, no matching Stripe refund

    result = ReconciliationService.run(stripe: {
      "re_match"   => { amount: 50_00 },
      "re_wrong"   => { amount: 50_00 },
      "re_missing" => { amount: 18_00 }    # Stripe refunded, ledger never recorded it
    })

    assert_equal 1, result.matched
    assert_equal [ "re_missing" ], result.missing.map { |m| m[:stripe_refund_id] }
    assert_equal [ "re_wrong" ],   result.mismatched.map { |m| m[:stripe_refund_id] }
    assert_equal 50_00, result.mismatched.first[:stripe_cents]
    assert_equal 40_00, result.mismatched.first[:ledger_cents]
    assert_includes result.orphans.map { |o| o[:stripe_refund_id] }, "re_orphan"
    refute result.ok?, "missing, mismatch, or orphan must fail reconciliation"
  end
end
