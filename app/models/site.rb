# frozen_string_literal: true

# The one site this install serves. An install is one customer's CMS: its
# own process, database and data directory, reached at APP_HOST.
#
#   Site.host  # => "acme.librepublish.com"  (APP_HOST, else the site URL's host)
#   Site.key   # => "acme"                   (SITE_KEY, else the host's first label)
#
# `key` is what the API has always sent as `tenant` (manifest, webhook
# envelopes, device login's `account`) and what integrations tell sites apart
# by, so it has to stay the same when an install moves hosts.
module Site
  module_function

  # APP_HOST, else the host of the site's own address (Settings › General):
  # Libre Publish lives on the website's host, at /cms, so a host that never
  # heard of APP_HOST still gets right links once the site URL is set.
  def host
    Rails.configuration.x.app_host.presence || site_url_host || "localhost"
  end

  # The public website's own address, for what its pages and sitemap print
  # about themselves (canonical, og:url, JSON-LD, sitemap.xml): the site URL
  # (Settings › General), else this install's APP_HOST. Never the request's
  # Host header, which whoever sends a request chooses, and which a shared
  # cache would keep in a page for everyone. nil with neither set (a fresh
  # development copy), where the caller falls back to the request.
  def public_base_url
    configured = Setting.get("general")["site_base_url"].to_s.strip.chomp("/")
    return configured if configured.present?

    app_host = Rails.configuration.x.app_host.presence or return
    "#{Rails.configuration.x.app_protocol || "https"}://#{app_host}"
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def site_url_host
    uri = URI.parse(Setting.get("general")["site_base_url"].to_s.strip)
    return unless uri.host

    uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
  rescue URI::InvalidURIError, ActiveRecord::ActiveRecordError
    nil
  end

  def key
    Rails.configuration.x.site_key.presence || host.split(":").first.to_s.split(".").first.to_s
  end

  # The site's own time zone (Settings › General), which the admin shows and
  # reads every time in. Stored times stay UTC. Falls back to the server's
  # zone when unset or unknown.
  def time_zone
    name = Setting.get("general")["timezone"].presence
    (name && Time.find_zone(name)) || server_time_zone
  rescue ActiveRecord::ActiveRecordError
    server_time_zone
  end

  def server_time_zone
    Time.find_zone(ENV["TZ"].presence || system_zone_name.to_s) || Time.find_zone("UTC")
  end

  # The system zone's IANA name, from /etc/localtime's link (".../zoneinfo/America/New_York").
  def system_zone_name
    File.readlink("/etc/localtime").split("zoneinfo/").last
  rescue SystemCallError
    nil
  end

  # For links built outside a request (mailers, jobs, the CLI bootstrap).
  # The admin's own host when it has one (CMS_ADMIN_HOST, AdminHost), else nil.
  def admin_host = Rails.configuration.x.admin_host.presence

  # For links into the admin (a password reset, a notification's "open it"):
  # the admin's own host when it has one.
  def url_options
    name, port = (admin_host || host).split(":", 2)
    {host: name, port: port&.to_i, protocol: Rails.configuration.x.app_protocol}.compact
  end
end
