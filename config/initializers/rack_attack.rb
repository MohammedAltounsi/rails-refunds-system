# Rate-limiting for the public, always-on deploy. Counters live in Rails.cache
# (solid_cache in production). rack-attack auto-inserts its middleware via a
# Railtie, so configuring it here is enough.
class Rack::Attack
  Rack::Attack.enabled = !Rails.env.test?

  # Static assets and the healthcheck never count against a limit.
  safelist("assets/health") do |req|
    req.path.start_with?("/assets") || req.path == "/up"
  end

  # Baseline: 300 requests / 5 min / IP across the whole app.
  throttle("req/ip", limit: 300, period: 5.minutes) { |req| req.ip }

  # The refund-issuing endpoint is the abuse surface (spamming refund creation
  # against a real Stripe account): tighter at 20 / min / IP.
  throttle("writes/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/refunds")
  end

  self.throttled_responder = lambda do |_req|
    [ 429, { "content-type" => "text/plain" }, [ "Too many requests. Slow down and try again shortly.\n" ] ]
  end
end
