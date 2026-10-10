# frozen_string_literal: true

# One row per outbound webhook attempt. Append-only — the index page reads
# the most-recent few per webhook for a quick "is this thing healthy?" view.
# `payload` is truncated by Webhook::Deliverable to keep rows bounded; what
# the receiver answered is kept as its status only.
class WebhookDelivery < ApplicationRecord
  belongs_to :webhook, inverse_of: :deliveries

  scope :recent, ->(n = 25) { order(created_at: :desc).limit(n) }
end
