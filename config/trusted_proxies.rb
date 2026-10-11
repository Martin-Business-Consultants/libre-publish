# frozen_string_literal: true

require "ipaddr"

# The proxies in front of the install whose X-Forwarded-For the app believes
# (CMS_TRUSTED_PROXIES), so request.remote_ip is the visitor's address and
# not the proxy's: rate limits, the audit log and API token use all key on
# it. Behind Cloudflare without this, every visitor that reaches the site
# through one Cloudflare data center shares one address, and so one rate
# limit.
#
#   CMS_TRUSTED_PROXIES=cloudflare
#   CMS_TRUSTED_PROXIES=cloudflare,203.0.113.0/24
#
# `cloudflare` is Cloudflare's published ranges; anything else is an address
# or a CIDR range. Rails' own (localhost and private networks, where
# kamal-proxy and Thruster are) are always trusted. Not in Zeitwerk's lib/,
# since config/application.rb reads it before the autoloader runs.
module TrustedProxies
  extend self

  # https://www.cloudflare.com/ips/ (checked 2026-10-11). They change
  # rarely, and Cloudflare announces it ahead of time.
  CLOUDFLARE = %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
    108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17
    162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32
    2a06:98c0::/29 2c0f:f248::/32
  ].freeze

  NAMED = {"cloudflare" => CLOUDFLARE}.freeze

  # The entries of a CMS_TRUSTED_PROXIES value: [ranges, the ones it couldn't read].
  def parse(value)
    entries = value.to_s.split(",").map(&:strip).reject(&:empty?)
    ranges, invalid = [], []
    entries.each do |entry|
      (NAMED[entry.downcase] || [entry]).each do |range|
        ranges << IPAddr.new(range)
      rescue IPAddr::Error
        invalid << entry
      end
    end
    [ranges, invalid]
  end

  # What config.action_dispatch.trusted_proxies takes, or nil to keep Rails'
  # own when none are given. A list replaces Rails' own, so it carries them.
  def for_rails(value)
    ranges, = parse(value)
    ActionDispatch::RemoteIp::TRUSTED_PROXIES + ranges if ranges.any?
  end
end
