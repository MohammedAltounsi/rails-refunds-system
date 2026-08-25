class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Access control that is enforced only when configured, so the public showcase
  # stays open by design while a real deployment locks money-moving actions
  # behind Basic auth. Set ADMIN_PASSWORD (and optionally ADMIN_USER) to require
  # it. Read-only ledger/reconciliation pages are always public — they are the
  # exhibit.
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
