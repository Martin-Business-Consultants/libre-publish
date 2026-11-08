# frozen_string_literal: true

# Delivers one event to one webhook (Webhook::Deliverable#deliver_now).
# One attempt: a failure, network errors included, is recorded as a failed
# delivery (and counts toward Webhook#record_attempt!), not retried.
class Webhook::DeliveryJob < ApplicationJob
  queue_as :default

  # `_tenant` is only for jobs queued before this app became a single install;
  # it's ignored. Drop it once those have drained.
  def perform(webhook_id, event, payload, _tenant = nil)
    Webhook.find_by(id: webhook_id)&.deliver_now(event, payload)
  end
end
