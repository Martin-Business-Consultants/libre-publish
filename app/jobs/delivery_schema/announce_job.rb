# frozen_string_literal: true

# Reads the delivery schema's digest once writes have settled, and announces
# schema.changed when it moved (DeliverySchema.announce_now).
class DeliverySchema::AnnounceJob < ApplicationJob
  queue_as :default

  def perform
    DeliverySchema.announce_now
  end
end
