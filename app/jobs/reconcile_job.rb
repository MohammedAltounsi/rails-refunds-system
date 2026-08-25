# Continuous reconciliation: run the ledger-vs-Stripe check and persist the
# result as a ReconciliationRun. Scheduled (a cron on Render, or via
# `rails reconcile`). Storing every run builds a timeline of drift, so we
# can see when it first appeared.
class ReconcileJob < ApplicationJob
  queue_as :default

  def perform
    result = ReconciliationService.run
    run = ReconciliationRun.record!(result)
    Rails.logger.warn("ReconcileJob: #{run.status} (missing #{run.missing_count}, mismatch #{run.mismatched_count}, orphan #{run.orphan_count})") unless run.clean?
    run
  end
end
