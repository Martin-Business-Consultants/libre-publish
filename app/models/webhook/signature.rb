# frozen_string_literal: true

require "openssl"

# How the CMS signs what it posts to a site or a receiver — webhooks
# (Webhook::Deliverable) and an on-demand site's purges (Deploys::Purge) —
# as the Go core does (docs/webhooks.md, spec/fixtures/contracts/go):
#
#   X-CMS-Signature:    sha256=<hex HMAC-SHA256 of the body>
#   X-CMS-Signature-V2: sha256=<hex HMAC-SHA256 of "<X-CMS-Timestamp>.<body>">
#   X-CMS-Timestamp:    <Unix seconds when it was signed; each attempt afresh>
#   X-CMS-Delivery:     <the delivery's id, the same on every retry of it>
#
# A receiver checks V2 and the timestamp's age (five minutes is the advised
# tolerance) to refuse a replayed post, and drops a delivery id it has
# already handled. The first signature is kept for receivers written before
# V2.
module Webhook::Signature
  module_function

  def headers(body, secret, delivery_id:, at: Time.current)
    timestamp = at.to_i.to_s
    {
      "X-CMS-Signature" => sign(body, secret),
      "X-CMS-Signature-V2" => sign("#{timestamp}.#{body}", secret),
      "X-CMS-Timestamp" => timestamp,
      "X-CMS-Delivery" => delivery_id.to_s
    }
  end

  def sign(text, secret) = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, text)}"
end
