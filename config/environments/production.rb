# frozen_string_literal: true

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
  config.public_file_server.headers = {"cache-control" => "public, max-age=#{1.year.to_i}"}

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # ASSUME_SSL=true behind a proxy that terminates TLS and forwards plain HTTP
  # (Cloudflare, a load balancer): every request is treated as HTTPS.
  config.assume_ssl = ENV["ASSUME_SSL"] == "true"

  # HTTPS only: HTTP redirects to HTTPS, Strict-Transport-Security, Secure
  # cookies. On whenever links are https (APP_PROTOCOL, the default);
  # CMS_FORCE_SSL=false turns it off for an install served over plain HTTP.
  # The health check (/up) and local addresses are never redirected, so
  # kamal-proxy and a container on localhost still reach the app.
  config.force_ssl = ENV.fetch("CMS_FORCE_SSL") { (ENV.fetch("APP_PROTOCOL", "https") == "https").to_s } == "true"
  config.ssl_options = {
    redirect: {exclude: ->(request) { request.path == "/up" || %w[localhost 127.0.0.1 ::1].include?(request.host) }}
  }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = {database: {writing: :queue}}

  # Where this install is reached (Site.host): mail links, the agent
  # bootstrap, anything built outside a request. Set APP_HOST per install.
  config.x.app_host = ENV.fetch("APP_HOST", "localhost")
  config.x.app_protocol = ENV.fetch("APP_PROTOCOL", "https")
  config.action_mailer.default_url_options = {host: config.x.app_host, protocol: config.x.app_protocol}

  # Outbound email over SMTP, from the install's environment (SMTP_*). It
  # defaults to Outsend's relay (plain auth, username "outsend", the API key
  # as SMTP_PASSWORD). Short timeouts fail the delivery job fast instead of
  # hanging on connect.
  config.action_mailer.delivery_method    = :smtp
  config.action_mailer.perform_deliveries = true
  # Deliveries run in Solid Queue, so a raised error retries the job and
  # shows up in the queue instead of silently dropping a password reset.
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address:        ENV.fetch("SMTP_ADDRESS", "smtp.getoutsend.com"),
    port:           ENV.fetch("SMTP_PORT", 2587).to_i,
    user_name:      ENV.fetch("SMTP_USERNAME", "outsend"),
    password:       ENV["SMTP_PASSWORD"],
    authentication: :plain,
    open_timeout:   5,
    read_timeout:   5
  }.merge(
    # Keeps the connection encrypted but stops verifying the relay's
    # certificate: only for a relay whose certificate has lapsed.
    ENV["SMTP_INSECURE_TLS"].present? ? {openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE} : {}
  )

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
