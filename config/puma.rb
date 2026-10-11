# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Workers, restarted one at a time, so a plugin, a theme or an update going
# live never leaves a visitor waiting (lib/puma/plugin/cms_restart.rb). Only
# when Puma itself is the server (bin/web): `rails server` loads the app
# before Puma starts, so a restart there is the ordinary kind. Two in
# production unless WEB_CONCURRENCY says otherwise; none elsewhere.
workers_count = Integer(ENV.fetch("WEB_CONCURRENCY") { (ENV["RAILS_ENV"] == "production") ? "2" : "0" })
clustered = workers_count.positive? && !defined?(Rails::Server)

if clustered
  # Upgrade::InPlace switches without downtime only when it is.
  ENV["CMS_PUMA_CLUSTERED"] = "1"
  workers workers_count
  # Puma's parent holds no gems of the app's, so a worker can load a newer
  # release's bundle (Upgrade::InPlace).
  prune_bundler
  # A symlink to the release that runs (bin/docker-entrypoint): each worker
  # a phased restart starts changes into it again, and loads what it points at.
  directory ENV["CMS_APP_DIR"] unless ENV["CMS_APP_DIR"].to_s.empty?

  before_worker_boot do
    dir = File.realpath(ENV["CMS_APP_DIR"].to_s.empty? ? Dir.pwd : ENV["CMS_APP_DIR"])
    bundle = File.join(dir, "bundle")
    ENV["BUNDLE_GEMFILE"] = File.join(dir, "Gemfile")
    ENV["BUNDLE_PATH"] = File.directory?(bundle) ? bundle : (ENV["CMS_IMAGE_BUNDLE_PATH"] || ENV["BUNDLE_PATH"])
    # This Ruby runs the release (the update checked it's the same version),
    # rather than its own copy (config/bundled_ruby.rb).
    ENV["CMS_BUNDLED_RUBY"] ||= RbConfig.ruby
  end
end

# `bin/rails restart` (tmp/restart.txt): a phased restart with workers, the
# ordinary kind without; and, with workers, the background jobs.
require_relative "../lib/puma/plugin/cms_restart"
plugin :cms_restart

# Without workers, the Solid Queue supervisor runs inside Puma for
# single-server deployments, as Rails sets it up.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] && !clustered

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
