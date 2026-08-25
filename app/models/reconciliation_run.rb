# A stored snapshot of one reconciliation. Continuous reconciliation runs on a
# schedule (ReconcileJob) and persists a row here, so the safety net has a
# history — you can see the moment drift first appeared, not just that it exists
# now. The live page reads the latest run alongside an on-demand check.
class ReconciliationRun < ApplicationRecord
  scope :recent, -> { order(created_at: :desc) }

  def self.record!(result)
    create!(
      status:           status_for(result),
      stripe_count:     result.stripe_count,
      matched:          result.matched,
      missing_count:    result.missing.size,
      mismatched_count: result.mismatched.size,
      orphan_count:     result.orphans.size,
      global_sum_cents: result.global_sum_cents,
      invariants_ok:    result.invariants_hold?
    )
  end

  def self.status_for(result)
    return "unreachable" if result.unreachable?
    result.ok? ? "clean" : "drift"
  end

  def clean?       = status == "clean"
  def drift?       = status == "drift"
  def unreachable? = status == "unreachable"
end
