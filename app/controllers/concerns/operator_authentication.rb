# Access control that is enforced only when configured, so the public showcase
# stays open by design while a real deployment locks money-moving actions behind
# Basic auth. Set ADMIN_PASSWORD (and optionally ADMIN_USER) to require it.
# Shared by the HTML controllers and the JSON API so neither is a hole.
module OperatorAuthentication
  extend ActiveSupport::Concern

  # ActionController::API does not bring the HTTP Basic helpers that
  # ActionController::Base includes by default, so pull them in here — the API
  # controller relies on this concern for exactly the same auth as the HTML one.
  included do
    include ActionController::HttpAuthentication::Basic::ControllerMethods
  end

  private

  def require_operator!
    return unless ENV["ADMIN_PASSWORD"].present?

    authenticate_or_request_with_http_basic("Refunds & Payouts") do |user, password|
      ActiveSupport::SecurityUtils.secure_compare(user, ENV.fetch("ADMIN_USER", "operator")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV["ADMIN_PASSWORD"])
    end
  end

  # The person on the hook for an action: the authenticated user, or "demo".
  def current_actor
    return "demo" if ENV["ADMIN_PASSWORD"].blank?

    ActionController::HttpAuthentication::Basic.user_name_and_password(request)&.first || "demo"
  end
end
