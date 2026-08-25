require "test_helper"

# The demo lets a visitor play Stripe's webhook so they can drive a refund
# through its whole lifecycle by clicking. It must use the real convergent
# methods (so the demo is faithful) and must be OFF in production (so it is not
# a back door that settles money without a verified webhook).
class DemoSimulateTest < ActionDispatch::IntegrationTest
  def with_demo(on)
    original = Rails.configuration.x.demo_mode
    Rails.configuration.x.demo_mode = on
    yield
  ensure
    Rails.configuration.x.demo_mode = original
  end

  test "in demo mode a visitor issues a refund and settles it end to end" do
    with_demo(true) do
      charge = Charge.capture!(stripe_payment_intent_id: "pi_demo_#{SecureRandom.hex(3)}", amount_cents: 5000)

      # Issue reaches `processing` with no Stripe account wired (gateway stub).
      post refunds_path, params: { charge_id: charge.id, amount_cents: 2000 }
      refund = Refund.order(:created_at).last
      assert_equal "processing", refund.status

      # Playing "Stripe settles" books the reversal exactly once.
      assert_difference -> { Entry.where(idempotency_key: "refund-settle:#{refund.id}").count }, 1 do
        post simulate_refund_path(refund, outcome: "succeeded")
      end
      assert_equal "settled", refund.reload.status
      assert_equal 0, Posting.sum(:amount_cents), "the book still sums to zero"
    end
  end

  test "simulate is refused when demo mode is off, so money is not moved without a webhook" do
    charge = Charge.capture!(stripe_payment_intent_id: "pi_off_#{SecureRandom.hex(3)}", amount_cents: 5000)
    refund = Refund.request!(charge: charge, amount_cents: 1000, idempotency_key: "off-#{SecureRandom.hex(3)}")
    refund.mark_processing!(stripe_refund_id: "re_x")

    with_demo(false) do
      assert_no_difference -> { Entry.where(idempotency_key: "refund-settle:#{refund.id}").count } do
        post simulate_refund_path(refund, outcome: "succeeded")
      end
    end
    assert_equal "processing", refund.reload.status, "off means only a real webhook can settle"
  end
end
