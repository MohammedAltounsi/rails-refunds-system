# Be sure to restart your server when you modify this file.
# Application-wide Content Security Policy.
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# This app has no browser payment form (refunds are issued server-side against
# Stripe's Refund API, never collected from a customer), so the policy is tight
# and does not need to allowlist Stripe.js or any frame.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.form_action     :self
    policy.object_src      :none
    policy.frame_ancestors :none
    policy.img_src         :self, :data
    policy.font_src        :self, :data, "https://fonts.gstatic.com"
    policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.script_src      :self
    policy.connect_src     :self
  end

  # Nonce the inline importmap/module scripts so they run without 'unsafe-inline'.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
