# Rate-limiting for the public, always-on deploy. rack-attack auto-inserts its
# middleware via a Railtie, so configuring it here is enough.
#
# Counters live in a process-local memory store, which is correct ONLY because
# the deploy runs a single Puma worker (WEB_CONCURRENCY=1, see render.yaml — the
# 512 MB Starter instance can't hold more). With one process the count is global.
# ponytail: per-process store, single worker. If WEB_CONCURRENCY ever rises,
# back this with a shared store (Redis or solid_cache) or the limit multiplies
# by worker count.
class Rack::Attack
  Rack::Attack.enabled = !Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Static assets and the healthcheck never count against a limit.
  safelist("assets/health") do |req|
    req.path.start_with?("/assets") || req.path == "/up"
  end

  # Baseline: 300 requests / 5 min / IP across the whole app.
  throttle("req/ip", limit: 300, period: 5.minutes) { |req| req.ip }

  # The money-moving endpoints are the abuse surface (spamming refund/payout
  # creation against a real Stripe account, via the UI or the JSON API): tighter
  # at 20 / min / IP.
  throttle("writes/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/refunds", "/payouts", "/api/refunds")
  end

  self.throttled_responder = lambda do |_req|
    [ 429, { "content-type" => "text/plain" }, [ "Too many requests. Slow down and try again shortly.\n" ] ]
  end
end
