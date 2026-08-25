class ReconciliationController < ApplicationController
  # The report walks every Stripe refund, so an uncached public endpoint is a
  # free amplification/DoS vector against the Stripe API rate limit. Cache the
  # result: at most one Stripe scan every 5 minutes no matter the traffic.
  # rack-attack throttles the endpoint on top of this.
  def show
    # On a cache miss, run reconciliation and persist the run — so even without
    # the scheduled ReconcileJob the page builds a visible history of checks.
    @result = Rails.cache.fetch("reconciliation:v1", expires_in: 5.minutes) do
      ReconciliationService.run.tap { |r| ReconciliationRun.record!(r) }
    end
    @recent_runs   = ReconciliationRun.recent.limit(10)
    @events        = StripeEvent.group(:status).count
    @failed_events = StripeEvent.failed.order(created_at: :desc).limit(10)
  end
end
