# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "resolv"

# A URL the CMS sends requests to because someone typed it in — a webhook, a
# build hook, a site's purge endpoint — checked so it can't be pointed back
# into the network the CMS runs in: loopback, private ranges, link-local
# (cloud metadata at 169.254.169.254), carrier-grade NAT, multicast and the
# IPv6 equivalents, including IPv4 addresses written as IPv6.
#
# The host is resolved once and the request is pinned to the address that
# was checked (Net::HTTP#ipaddr=), so a name that resolves somewhere public
# when it's checked and somewhere private when it's fetched (DNS rebinding)
# still reaches the public one. Nothing here follows redirects.
#
#   uri, http = OutboundUrl.connect(url, open_timeout: 5, read_timeout: 10)
#   http.request(Net::HTTP::Post.new(uri.request_uri))
#
# A self-hosted install whose receivers live on its own network sets
# CMS_ALLOW_PRIVATE_WEBHOOKS=true. Development allows them unless it's set
# to false; production and test block them.
module OutboundUrl
  class Unsafe < StandardError; end

  BLOCKED = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 64:ff9b::/96 2002::/16
  ].map { IPAddr.new(it) }.freeze

  module_function

  # The parsed URL and the address to send it to; raises Unsafe when it isn't
  # an http(s) URL, doesn't resolve, or resolves only to a blocked address.
  def check!(url)
    uri = parse(url)
    raise Unsafe, "must be an http(s) URL" unless uri

    addresses = resolve(uri.hostname)
    raise Unsafe, "#{uri.host} doesn't resolve" if addresses.empty?
    return [uri, addresses.first] if allow_private?

    allowed = addresses.reject { blocked?(it) }
    raise Unsafe, "#{uri.host} is a private or local address" if allowed.empty?

    [uri, allowed.first]
  end

  # For a validation: the reason a URL may not be saved, or nil. A host that
  # doesn't resolve yet passes — the check at send time still applies.
  def problem_with(url)
    uri = parse(url)
    return "must be an http(s) URL" unless uri
    return if allow_private?

    "can't point at a private or local address" if resolve(uri.hostname).any? { blocked?(it) }
  end

  # Net::HTTP for the URL, connecting to the address that was checked.
  def connect(url, open_timeout:, read_timeout:)
    uri, address = check!(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    [uri, http]
  end

  def blocked?(address)
    ip = IPAddr.new(address.to_s)
    ip = ip.native if ip.ipv6? && (ip.ipv4_mapped? || ip.ipv4_compat?)
    BLOCKED.any? { it.family == ip.family && it.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def allow_private?
    setting = ENV["CMS_ALLOW_PRIVATE_WEBHOOKS"]
    return ActiveModel::Type::Boolean.new.cast(setting) == true if setting.present?

    Rails.env.development?
  end

  # Every address the host resolves to; an IP literal is its own answer.
  def resolve(host)
    return [] if host.blank?
    return [IPAddr.new(host).to_s] if ip_literal?(host)

    resolver.call(host)
  rescue Resolv::ResolvError, SocketError
    []
  end

  # Swappable, so tests needn't touch DNS.
  def resolver = @resolver || ->(host) { Resolv.getaddresses(host) }
  def resolver=(callable)
    @resolver = callable
  end

  def parse(url)
    uri = URI.parse(url.to_s.strip)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  def ip_literal?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::InvalidAddressError
    false
  end
end
