require "test_helper"

class RefundsControllerTest < ActionDispatch::IntegrationTest
  def processing_refund
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: 10_00)
    refund = Refund.request!(charge: charge, amount_cents: 4_00, idempotency_key: "rc-#{SecureRandom.hex(4)}")
    refund.mark_processing!(stripe_refund_id: "re_#{SecureRandom.hex(4)}")
    refund
  end

  test "replay refuses to settle a processing refund (no back door around the webhook)" do
    refund = processing_refund

    assert_no_difference -> { Posting.count } do
      post replay_refund_path(refund)
    end
    assert_equal "processing", refund.reload.status, "money is booked only on a verified webhook, never via replay"
  end

  test "replay on a settled refund keeps it booked exactly once" do
    refund = processing_refund
    refund.settle!

    post replay_refund_path(refund)

    assert_redirected_to refund
    assert_equal 1, Entry.where(idempotency_key: "refund-settle:#{refund.id}").count
  end
end
