require "test_helper"

class RefundTest < ActiveSupport::TestCase
  setup do
    @charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: 10_00)
  end

  test "every legal transition is allowed" do
    refund = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "k1")
    assert_equal "requested", refund.status

    refund.mark_processing!(stripe_refund_id: "re_1")
    assert_equal "processing", refund.status

    refund.settle!
    assert_equal "settled", refund.status
  end

  test "requested can also fail directly, without ever processing" do
    refund = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "k2")
    refund.fail!("card no longer valid")
    assert_equal "failed", refund.status
    assert_equal "card no longer valid", refund.failure_reason
  end

  test "processing can fail" do
    refund = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "k3")
    refund.mark_processing!(stripe_refund_id: "re_3")
    refund.fail!("stripe declined the reversal")
    assert_equal "failed", refund.status
  end

  test "every illegal transition raises and changes nothing" do
    refund = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "k4")

    assert_raises(Refund::InvalidTransition) { refund.settle! }              # requested -> settled: skips processing
    assert_equal "requested", refund.reload.status

    refund.mark_processing!(stripe_refund_id: "re_4")
    assert_raises(Refund::InvalidTransition) { refund.mark_processing!(stripe_refund_id: "re_4b") } # processing -> processing
    assert_equal "processing", refund.reload.status

    refund.settle!
    assert_raises(Refund::InvalidTransition) { refund.fail!("too late") }    # settled -> failed
    assert_equal "settled", refund.reload.status

    other = Refund.request!(charge: @charge, amount_cents: 1_00, idempotency_key: "k4b")
    other.fail!("declined")
    assert_raises(Refund::InvalidTransition) { other.mark_processing!(stripe_refund_id: "re_x") } # failed -> processing
  end

  test "a partial refund is accepted up to the captured amount" do
    Refund.request!(charge: @charge, amount_cents: 4_00, idempotency_key: "p1")
    Refund.request!(charge: @charge, amount_cents: 6_00, idempotency_key: "p2")
    assert_equal 0, @charge.reload.refundable_cents
  end

  test "over-refunding a charge is rejected, even split across requests" do
    Refund.request!(charge: @charge, amount_cents: 6_00, idempotency_key: "o1")
    assert_raises(Refund::OverRefund) do
      Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "o2") # 6+5 > 10
    end
    assert_equal 6_00, @charge.reload.refunded_cents
  end

  test "a failed refund frees up its reserved amount for a new refund" do
    first = Refund.request!(charge: @charge, amount_cents: 10_00, idempotency_key: "f1")
    first.fail!("declined")
    assert_equal 10_00, @charge.reload.refundable_cents

    second = Refund.request!(charge: @charge, amount_cents: 10_00, idempotency_key: "f2")
    assert_equal "requested", second.status
  end

  test "requesting with the same idempotency key twice returns the same refund, not a duplicate" do
    r1 = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "dup")
    r2 = Refund.request!(charge: @charge, amount_cents: 5_00, idempotency_key: "dup")
    assert_equal r1.id, r2.id
    assert_equal 1, Refund.where(idempotency_key: "dup").count
  end

  test "settling posts a balancing reversal, and a repeat settle does not double it" do
    refund = Refund.request!(charge: @charge, amount_cents: 4_00, idempotency_key: "s1")
    refund.mark_processing!(stripe_refund_id: "re_s1")

    refund.settle!
    refund.settle! # redelivered webhook — must be a no-op, not a second reversal

    assert_equal 1, Entry.where(idempotency_key: "refund-settle:#{refund.id}").count
    assert_equal 10_00 - 4_00, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents, "reversed once, not twice"
  end

  test "the ledger stays balanced through a capture and a partial settle" do
    refund = Refund.request!(charge: @charge, amount_cents: 4_00, idempotency_key: "bal1")
    refund.mark_processing!(stripe_refund_id: "re_bal1")
    refund.settle!

    assert_equal 0, Posting.sum(:amount_cents), "the whole ledger must always sum to zero"
    assert_equal 10_00 - 4_00, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents
  end
end
