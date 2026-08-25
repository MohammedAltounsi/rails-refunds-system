require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Render terminates TLS at the edge, so trust the proxy and force HTTPS: this
  # sets Secure cookies, HSTS, and an http->https redirect (except the healthcheck).
  config.assume_ssl = true
  config.force_ssl  = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Tag every log line with the request id, so a single webhook or refund can be
  # traced end to end across the log.
  config.log_tags = [ :request_id ]

  # In-process memory cache. This app caches nothing that holds money, so a
  # durable store (Solid Cache) would add a database table for no benefit.
  config.cache_store = :memory_store

  # No background jobs in this app (refunds book on the webhook request itself);
  # :async is the lightest adapter and needs no separate worker process/memory.
  config.active_job.queue_adapter = :async

  # No outgoing mail in this app, so skip SMTP configuration entirely.
  config.action_mailer.perform_deliveries = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS-rebinding / Host-header protection: only serve the app's own host(s).
  config.hosts = [ ENV["APP_HOST"], /.*\.onrender\.com/ ].compact
  config.hosts << "localhost" if ENV["APP_HOST"].blank?
  # Skip host authorization for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
