require "test_helper"

class ReconciliationRunTest < ActiveSupport::TestCase
  def result(missing: [], mismatched: [], orphans: [], reachable: true, global_sum: 0)
    ReconciliationService::Result.new(
      stripe_count: 3, matched: 2, missing: missing, mismatched: mismatched, orphans: orphans,
      unbalanced_entries: [], global_sum_cents: global_sum, stripe_reachable: reachable
    )
  end

  test "records a clean run" do
    run = ReconciliationRun.record!(result)
    assert run.clean?
    assert_equal 2, run.matched
    assert run.invariants_ok
  end

  test "records a drift run with counts" do
    run = ReconciliationRun.record!(result(missing: [ { x: 1 } ], orphans: [ { y: 2 }, { z: 3 } ]))
    assert run.drift?
    assert_equal 1, run.missing_count
    assert_equal 2, run.orphan_count
  end

  test "records an unreachable run" do
    run = ReconciliationRun.record!(result(reachable: false))
    assert run.unreachable?
  end
end
