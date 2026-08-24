# The over-refund guarantee has two layers, and the DB layer is PostgreSQL-only:
#   1. app layer — Refund.request! locks the charge row (SELECT ... FOR UPDATE)
#      so two concurrent refund requests serialize instead of both reading a
#      stale "remaining" amount.
#   2. db layer  — the refunds_cannot_exceed_charge deferred trigger
#      (db_constraints.rake) rejects, at COMMIT, any refund total that exceeds
#      what the charge captured.
#
# SQLite (the local dev/test default) has neither, so these tests skip there.
# CI runs the suite against Postgres with the triggers installed. Threads need
# real committed rows, so transactional fixtures are off for this class.
class RefundConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  POSTGRES = ActiveRecord::Base.connection.adapter_name.match?(/postg/i)

  setup do
    skip "over-refund DB guarantees are PostgreSQL-only" unless POSTGRES
    @charge = Charge.capture!(stripe_payment_intent_id: "pi_race_#{SecureRandom.hex(4)}", amount_cents: 100_00)
  end

  # This class commits real rows (no transactional rollback), so clean up or
  # they pollute other tests' global ledger sum. No fixtures, so this is safe.
  teardown do
    next unless POSTGRES
    Refund.where(charge_id: @charge.id).delete_all
    Posting.joins(:entry).where(entries: { idempotency_key: "charge-capture:#{@charge.stripe_payment_intent_id}" }).delete_all
    Entry.where(idempotency_key: "charge-capture:#{@charge.stripe_payment_intent_id}").destroy_all
    @charge.destroy
  end

  # Layer 2: the trigger is the ultimate backstop, independent of app code.
  # Bypass Refund.request!'s own check to prove the DATABASE refuses on its own.
  test "the over-refund trigger rejects a commit that exceeds the charge, even if app code forgets to check" do
    Refund.create!(charge: @charge, amount_cents: 70_00, idempotency_key: "bypass-1", status: "settled")
    assert_raises(ActiveRecord::StatementInvalid) do
      Refund.create!(charge: @charge, amount_cents: 40_00, idempotency_key: "bypass-2", status: "settled")
    end
  end

  # Layer 1: the row lock serializes two racing refund requests. Without it,
  # both threads read the same "remaining" amount, both pass the check, and
  # together they over-refund.
  test "two concurrent refund requests for more than remains cannot both succeed" do
    charge_id = @charge.id
    request = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        # A fresh instance per thread — with_lock's transaction/connection is
        # thread-local, and sharing one AR object across threads isn't safe.
        Refund.request!(charge: Charge.find(charge_id), amount_cents: 60_00, idempotency_key: "race-#{SecureRandom.uuid}")
        :ok
      rescue Refund::OverRefund
        :rejected
      end
    end

    results = [ Thread.new(&request), Thread.new(&request) ].map(&:value)

    assert_equal 1, results.count(:ok), "exactly one 60.00 refund should fit in a 100.00 charge, got #{results.inspect}"
    assert_equal 40_00, @charge.reload.refundable_cents
  end
end
