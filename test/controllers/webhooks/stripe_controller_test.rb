require "test_helper"

class Webhooks::StripeControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  setup { ENV["STRIPE_WEBHOOK_SECRET"] = SECRET }

  # Sign a payload exactly the way Stripe does, so construct_event accepts it.
  def signed_headers(payload)
    ts  = Time.now.to_i
    sig = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{ts}.#{payload}")
    { "Stripe-Signature" => "t=#{ts},v1=#{sig}", "CONTENT_TYPE" => "application/json" }
  end

  def refund_updated_event(event_id:, stripe_refund_id:, refund_id:, status:, amount:)
    {
      id: event_id,
      type: "refund.updated",
      data: { object: { id: stripe_refund_id, status: status, amount: amount,
                         failure_reason: status == "failed" ? "expired_or_canceled_card" : nil,
                         metadata: { refund_id: refund_id } } }
    }.to_json
  end

  def new_refund(amount_cents: 4_00, charge_amount: 10_00)
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: charge_amount)
    refund = Refund.request!(charge: charge, amount_cents: amount_cents, idempotency_key: "wh-#{SecureRandom.hex(4)}")
    refund.mark_processing!(stripe_refund_id: "re_#{SecureRandom.hex(4)}")
    refund
  end

  test "a succeeded refund.updated settles the refund and reverses the ledger once, even on redelivery" do
    refund = new_refund(amount_cents: 4_00, charge_amount: 10_00)
    payload = refund_updated_event(event_id: "evt_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                    refund_id: refund.id, status: "succeeded", amount: 4_00)

    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    assert_response :ok
    assert_equal "settled", refund.reload.status
    assert_equal 10_00 - 4_00, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents

    post "/webhooks/stripe", params: payload, headers: signed_headers(payload) # redelivery, same event id
    assert_response :ok
    assert_equal 1, Entry.where(idempotency_key: "refund-settle:#{refund.id}").count
  end

  test "a failed refund.updated marks the refund failed and books nothing" do
    refund = new_refund
    payload = refund_updated_event(event_id: "evt_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                    refund_id: refund.id, status: "failed", amount: 4_00)

    assert_no_difference -> { Posting.count } do
      post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    end
    assert_response :ok
    assert_equal "failed", refund.reload.status
    assert_match(/expired_or_canceled_card/, refund.failure_reason)
  end

  test "each event is recorded in the inbox and a redelivery is deduped" do
    refund = new_refund
    payload = refund_updated_event(event_id: "evt_inbox_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                    refund_id: refund.id, status: "succeeded", amount: 4_00)
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)

    assert_equal 1, StripeEvent.where(event_id: "evt_inbox_#{refund.id}").count, "one inbox row per event id"
    assert StripeEvent.find_by(event_id: "evt_inbox_#{refund.id}").processed?
  end

  test "a non-terminal refund.updated (pending) is recorded and acknowledged without moving money" do
    refund = new_refund
    payload = refund_updated_event(event_id: "evt_pending_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                    refund_id: refund.id, status: "pending", amount: 4_00)

    assert_no_difference -> { Posting.count } do
      post "/webhooks/stripe", params: payload, headers: signed_headers(payload)
    end
    assert_response :ok
    assert_equal "processing", refund.reload.status
  end

  test "an out-of-order succeeded event (arriving before we recorded processing) settles without a 500" do
    charge = Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: 10_00)
    refund = Refund.request!(charge: charge, amount_cents: 4_00, idempotency_key: "ooo-#{SecureRandom.hex(4)}")
    # NOTE: no mark_processing! — the refund is still "requested" when Stripe's
    # succeeded webhook lands. The strict FSM would raise here; the convergent
    # handler must not.
    payload = refund_updated_event(event_id: "evt_ooo_#{refund.id}", stripe_refund_id: "re_ooo_#{refund.id}",
                                    refund_id: refund.id, status: "succeeded", amount: 4_00)

    post "/webhooks/stripe", params: payload, headers: signed_headers(payload)

    assert_response :ok, "an out-of-order event must not 500-loop Stripe"
    assert_equal "settled", refund.reload.status
    assert_equal 10_00 - 4_00, Ledger.account(Ledger::REVENUE_ACCOUNT).balance_cents
  end

  test "a late failed event after settlement is acknowledged and leaves the money booked" do
    refund = new_refund
    succeeded = refund_updated_event(event_id: "evt_s_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                      refund_id: refund.id, status: "succeeded", amount: 4_00)
    post "/webhooks/stripe", params: succeeded, headers: signed_headers(succeeded)
    assert_equal "settled", refund.reload.status

    failed = refund_updated_event(event_id: "evt_f_#{refund.id}", stripe_refund_id: refund.stripe_refund_id,
                                   refund_id: refund.id, status: "failed", amount: 4_00)
    assert_no_difference -> { Posting.count } do
      post "/webhooks/stripe", params: failed, headers: signed_headers(failed)
    end
    assert_response :ok
    assert_equal "settled", refund.reload.status, "a stale failed never un-books settled money"
  end

  test "a forged signature is rejected and nothing settles" do
    refund = new_refund
    payload = refund_updated_event(event_id: "evt_forged", stripe_refund_id: refund.stripe_refund_id,
                                    refund_id: refund.id, status: "succeeded", amount: 4_00)

    post "/webhooks/stripe", params: payload,
         headers: { "Stripe-Signature" => "t=1,v1=deadbeef", "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_equal "processing", refund.reload.status
  end
end
