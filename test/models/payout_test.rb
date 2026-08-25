require "test_helper"

class PayoutTest < ActiveSupport::TestCase
  test "requesting a payout accrues the liability in the same transaction" do
    payout = Payout.request!(payee: "Vendor A", amount_cents: 50_00, idempotency_key: "p1")

    assert_equal "requested", payout.status
    assert_equal 50_00, Ledger.account(Ledger::PAYABLE_ACCOUNT).balance_cents, "we now owe the payee"
    assert_equal 0, Posting.sum(:amount_cents), "the ledger still sums to zero"
  end

  test "paying a payout disburses the cash and clears the liability, exactly once" do
    payout = Payout.request!(payee: "Vendor B", amount_cents: 30_00, idempotency_key: "p2")
    payout.mark_processing!(stripe_payout_id: "po_2")

    payout.pay!
    payout.pay! # redelivery / retry — must not disburse twice

    assert_equal "paid", payout.reload.status
    assert_equal 0, Ledger.account(Ledger::PAYABLE_ACCOUNT).balance_cents, "liability cleared"
    assert_equal 30_00, Ledger.account(Ledger::CASH_ACCOUNT).balance_cents
    assert_equal 1, Entry.where(idempotency_key: "payout-pay:#{payout.id}").count
    assert_equal 0, Posting.sum(:amount_cents)
  end

  test "every illegal payout transition raises and changes nothing" do
    payout = Payout.request!(payee: "Vendor C", amount_cents: 10_00, idempotency_key: "p3")

    assert_raises(Payout::InvalidTransition) { payout.pay! }   # requested -> paid: skips processing
    assert_equal "requested", payout.reload.status

    payout.mark_processing!(stripe_payout_id: "po_3")
    payout.pay!
    assert_raises(Payout::InvalidTransition) { payout.fail!("too late") } # paid -> failed
    assert_equal "paid", payout.reload.status
  end

  test "the same idempotency key returns the same payout, accrued once" do
    a = Payout.request!(payee: "Vendor D", amount_cents: 25_00, idempotency_key: "dup")
    b = Payout.request!(payee: "Vendor D", amount_cents: 25_00, idempotency_key: "dup")

    assert_equal a.id, b.id
    assert_equal 1, Payout.where(idempotency_key: "dup").count
    assert_equal 25_00, Ledger.account(Ledger::PAYABLE_ACCOUNT).balance_cents, "accrued once, not twice"
  end

  test "apply_stripe_paid! is convergent and ordering-tolerant" do
    payout = Payout.request!(payee: "Vendor E", amount_cents: 40_00, idempotency_key: "conv")

    payout.apply_stripe_paid!(stripe_payout_id: "po_e") # paid webhook arrives before processing recorded

    assert_equal "paid", payout.reload.status
    assert_equal 0, Ledger.account(Ledger::PAYABLE_ACCOUNT).balance_cents
    assert_equal 1, Entry.where(idempotency_key: "payout-pay:#{payout.id}").count
  end

  test "apply_stripe_failed! never un-books a paid payout" do
    payout = Payout.request!(payee: "Vendor F", amount_cents: 15_00, idempotency_key: "late")
    payout.mark_processing!(stripe_payout_id: "po_f")
    payout.pay!
    before = Posting.sum(:amount_cents)

    payout.apply_stripe_failed!("stripe: too late")

    assert_equal "paid", payout.reload.status
    assert_equal before, Posting.sum(:amount_cents)
  end
end
