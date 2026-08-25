require "test_helper"

class ReprocessStuckStripeEventsJobTest < ActiveSupport::TestCase
  test "it heals a settlement dropped after the event was recorded but never processed" do
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: 10_00)
    refund = Refund.request!(charge: charge, amount_cents: 4_00, idempotency_key: "sweep-#{SecureRandom.hex(4)}")
    refund.mark_processing!(stripe_refund_id: "re_sweep")

    # An inbox row recorded but never processed (a crash between record and settle).
    payload = {
      id: "evt_sweep", type: "refund.updated",
      data: { object: { id: "re_sweep", status: "succeeded", amount: 4_00,
                        metadata: { refund_id: refund.id } } }
    }.to_json
    inbox = StripeEvent.create!(event_id: "evt_sweep", event_type: "refund.updated", payload: payload, status: "received")

    healed = ReprocessStuckStripeEventsJob.new.perform(older_than_seconds: 0)

    assert_equal 1, healed
    assert_equal "settled", refund.reload.status, "the dropped settlement is now booked"
    assert inbox.reload.processed?
    assert_equal 10_00 - 4_00, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents
  end

  test "it is idempotent — reprocessing an already-settled refund books money once" do
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: 10_00)
    refund = Refund.request!(charge: charge, amount_cents: 4_00, idempotency_key: "sweep2-#{SecureRandom.hex(4)}")
    refund.mark_processing!(stripe_refund_id: "re_sweep2")
    refund.settle!

    payload = {
      id: "evt_sweep2", type: "refund.updated",
      data: { object: { id: "re_sweep2", status: "succeeded", amount: 4_00,
                        metadata: { refund_id: refund.id } } }
    }.to_json
    StripeEvent.create!(event_id: "evt_sweep2", event_type: "refund.updated", payload: payload, status: "failed")

    ReprocessStuckStripeEventsJob.new.perform(older_than_seconds: 0)

    assert_equal 1, Entry.where(idempotency_key: "refund-settle:#{refund.id}").count, "booked once, not twice"
  end
end
