# frozen_string_literal: true

require "net/http"

# A build-hook URL (Vercel, Netlify, any CI; Cloudflare's is Deploys::Cloudflare):
# an empty POST starts a build, so what changed isn't passed on. The URL can carry a secret in its path, so only its host is
# ever shown.
class Deploys::BuildHook < Deploys::Provider
  def self.label = "Build hook"

  def configured?
    url.start_with?("http")
  end

  def target
    URI.parse(url).host if url.present?
  rescue URI::InvalidURIError
    nil
  end

  def fire(reason:, changes: [])
    uri, http = OutboundUrl.connect(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    request = Net::HTTP::Post.new(uri.request_uri, {"User-Agent" => "librepublish-deploy/1"})
    attempt_from(http.request(request), nil)
  rescue StandardError => e
    attempt_from(nil, "#{e.class}: #{e.message}")
  end

  private

  def url = config["url"].to_s
end
