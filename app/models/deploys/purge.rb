# frozen_string_literal: true

require "net/http"
require "json"

# What a site that renders on demand gets instead of a rebuild: a signed POST
# to the webhook its build reported (Frontend.purge_url — the Astro
# integration's /_cms/webhook), naming what changed and the cache tags to
# drop (Deploys::Change). Signed as webhooks are, an HMAC-SHA256 of the body
# in X-CMS-Signature, with Frontend.purge_secret. `all: true` (Deploy now)
# asks for everything.
#
#   POST /_cms/webhook
#   X-CMS-Event: cms.purge
#   X-CMS-Signature: sha256=<hex>
#   {"event": "cms.purge", "reason": "page.published", "site": "acme", "all": false,
#    "tags": ["page:about", "pages", "sitemap"], "changes": [{…}], "sent_at": "…"}
module Deploys::Purge
  EVENT = "cms.purge"

  module_function

  def fire(reason:, changes:, all: false, url: Frontend.purge_url, secret: Frontend.purge_secret)
    body = JSON.generate(body(reason: reason, changes: changes, all: all))
    uri, http = OutboundUrl.connect(url, open_timeout: Deploys::Provider::OPEN_TIMEOUT, read_timeout: Deploys::Provider::READ_TIMEOUT)
    request = Net::HTTP::Post.new(uri.request_uri, {
      "Content-Type"    => "application/json",
      "User-Agent"      => "librepublish-deploy/1",
      "X-CMS-Event"     => EVENT,
      "X-CMS-Signature" => signature(body, secret)
    })
    request.body = body
    attempt(http.request(request), nil)
  rescue StandardError => e
    attempt(nil, "#{e.class}: #{e.message}")
  end

  def body(reason:, changes:, all:)
    {event: EVENT, reason: reason, site: Site.key, all: all, tags: changes.flat_map { Array(it["tags"]) }.uniq,
     changes: changes, sent_at: Time.current.iso8601}
  end

  def signature(body, secret) = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"

  def attempt(response, error)
    Deploys::Attempt.new(status: response.is_a?(Net::HTTPSuccess) ? "success" : "failure",
      http_status: response&.code&.to_i, error: error)
  end
end
