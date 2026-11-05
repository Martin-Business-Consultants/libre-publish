# frozen_string_literal: true

# Delivers one event to one webhook (Webhook::Deliverable#deliver_now), as
# one delivery however many attempts it takes: its id (X-CMS-Delivery) is the
# job's, which a retry keeps. An attempt that couldn't connect, or was
# answered 408, 429 or 5xx, is made again after 30s, 2m, 5m, 15m and 40m (six
# in all), then given up on, as docs/webhooks.md promises.
class Webhook::DeliveryJob < ApplicationJob
  # Raised to have the attempt made again later.
  class Undelivered < StandardError; end

  RETRY_WAITS = [30.seconds, 2.minutes, 5.minutes, 15.minutes, 40.minutes].freeze

  queue_as :default

  retry_on Undelivered, attempts: RETRY_WAITS.size + 1, wait: ->(executions) { RETRY_WAITS.fetch(executions - 1, RETRY_WAITS.last) }

  # `_tenant` is only for jobs queued before this app became a single install;
  # it's ignored. Drop it once those have drained.
  def perform(webhook_id, event, payload, _tenant = nil)
    webhook = Webhook.find_by(id: webhook_id) or return
    delivery = webhook.deliver_now(event, payload, delivery_id: job_id)
    raise Undelivered, "#{event} to webhook #{webhook_id}: #{delivery.error || delivery.response_status}" if delivery && webhook.retry?(delivery)
  end
end
