class ApplicationController < ActionController::Base
  include OperatorAuthentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # True only when the showcase opts in with DEMO_MODE=true; off by default.
  # Gates the "play Stripe's webhook" demo actions and their UI.
  def demo_mode?
    Rails.configuration.x.demo_mode
  end
  helper_method :demo_mode?
end
