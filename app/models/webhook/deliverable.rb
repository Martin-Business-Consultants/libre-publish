# frozen_string_literal: true

require "net/http"
require "openssl"

# Delivering an event to this webhook: POST the envelope, signed
# (Webhook::Signature: HMAC-SHA256 over the body, and over the time and the
# body), with the event's name (X-CMS-Event) and the delivery's id
# (X-CMS-Delivery), and record the attempt in `webhook_deliveries`.
# `deliver_later` queues it (Webhook::DeliveryJob), which sends it again
# when it couldn't connect or was answered 408, 429 or 5xx (`retry?`);
# `Webhook.deliver_later` queues it for every active webhook that wants the
# event and whose filter the payload matches.
module Webhook::Deliverable
  extend ActiveSupport::Concern

  PAYLOAD_TRUNCATE  = 16_000
  OPEN_TIMEOUT      = 5
  READ_TIMEOUT      = 10
  # Answers worth sending again: the receiver was busy or broken, not refusing.
  RETRY_STATUSES = [408, 429, *500..599].freeze

  class_methods do
    def deliver_later(event, payload)
      for_event(event).find_each do |webhook|
        webhook.deliver_later(event, payload) if webhook.matches_filter?(event, payload)
      end
    end
  end

  def deliver_later(event, payload)
    Webhook::DeliveryJob.perform_later(id, event, payload)
  end

  # A synthetic delivery, so whoever runs the receiving end can check it
  # works without waiting for a real content change.
  def deliver_test
    deliver_later("page.updated", {test: true, message: "Test delivery from CMS"})
    track_event(:test_fired)
  end

  # `delivery_id` names the delivery, the same on each retry of it (the
  # job's id); a delivery sent outside a job gets one of its own. Returns
  # the attempt's WebhookDelivery.
  def deliver_now(event, payload, delivery_id: SecureRandom.uuid)
    return unless active?

    body = JSON.generate(envelope(event, payload))
    started = monotonic_ms
    response, error = post(body, event:, delivery_id:)
    success = response.is_a?(Net::HTTPSuccess)

    record_delivery(event: event, body: body, response: response, error: error,
      duration: monotonic_ms - started, success: success).tap do
      record_attempt!(success: success)
    end
  end

  # Whether an attempt is worth making again: it couldn't connect or timed
  # out, or the receiver answered 408, 429 or 5xx. Any other answer is final.
  def retry?(delivery)
    !delivery.success && (delivery.response_status.nil? || RETRY_STATUSES.include?(delivery.response_status))
  end

  private

  # `tenant` keeps its name — receivers match on it — and carries Site.key.
  def envelope(event, payload)
    {
      event:        event,
      tenant:       Site.key,
      delivered_at: Time.current.iso8601,
      data:         payload
    }
  end

  # To the address OutboundUrl checked; a URL that now resolves somewhere
  # private is a failed delivery, not a request.
  def post(body, event:, delivery_id:)
    uri, http = OutboundUrl.connect(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)

    request = Net::HTTP::Post.new(uri.request_uri, {
      "Content-Type" => "application/json",
      "User-Agent"   => "librepublish-webhooks/1",
      "X-CMS-Event"  => event.to_s
    }.merge(Webhook::Signature.headers(body, secret, delivery_id:)).merge((headers || {}).to_h.transform_keys(&:to_s)))
    request.body = body

    [http.request(request), nil]
  rescue StandardError => e
    [nil, "#{e.class}: #{e.message}"]
  end

  def record_delivery(event:, body:, response:, error:, duration:, success:)
    deliveries.create!(
      event:           event,
      payload:         body.to_s.first(PAYLOAD_TRUNCATE),
      response_status: response&.code&.to_i,
      error:           error,
      duration_ms:     duration,
      success:         success,
      created_at:      Time.current
    )
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
