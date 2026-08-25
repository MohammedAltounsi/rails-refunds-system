require "test_helper"

class Api::RefundsControllerTest < ActionDispatch::IntegrationTest
  # Stand in for Stripe's Refund.create (no network in tests): returns an object
  # with a unique id, so RefundService marks the refund "processing" the way
  # real test-mode Stripe would. Saved/restored around each test.
  setup do
    @original_create = RefundGateway.method(:create)
    RefundGateway.define_singleton_method(:create) { |refund| Struct.new(:id).new("re_stub_#{refund.id}") }
  end

  teardown do
    RefundGateway.define_singleton_method(:create, @original_create)
  end

  def charge(amount = 100_00)
    Charge.capture!(stripe_payment_intent_id: "pi_#{SecureRandom.hex(4)}", amount_cents: amount)
  end

  test "POST issues a refund and returns it as JSON" do
    c = charge
    post "/api/refunds", params: { charge_id: c.id, amount_cents: 30_00 }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "processing", body["status"]
    assert_equal 30_00, body["amount_cents"]
    assert_equal c.stripe_payment_intent_id, body["charge"]
  end

  test "the same Idempotency-Key issues the refund once" do
    c = charge
    headers = { "Idempotency-Key" => "abc-123" }

    post "/api/refunds", params: { charge_id: c.id, amount_cents: 20_00 }, headers: headers
    first = JSON.parse(response.body)["id"]
    post "/api/refunds", params: { charge_id: c.id, amount_cents: 20_00 }, headers: headers
    second = JSON.parse(response.body)["id"]

    assert_equal first, second
    assert_equal 1, Refund.where(idempotency_key: "abc-123").count
  end

  test "an over-refund returns 422" do
    c = charge(10_00)
    post "/api/refunds", params: { charge_id: c.id, amount_cents: 20_00 }
    assert_response :unprocessable_entity
    assert_equal "over_refund", JSON.parse(response.body)["error"]
  end

  test "GET returns a refund and 404s an unknown one" do
    c = charge
    post "/api/refunds", params: { charge_id: c.id, amount_cents: 5_00 }
    id = JSON.parse(response.body)["id"]

    get "/api/refunds/#{id}"
    assert_response :ok
    assert_equal id, JSON.parse(response.body)["id"]

    get "/api/refunds/9999999"
    assert_response :not_found
  end
end
