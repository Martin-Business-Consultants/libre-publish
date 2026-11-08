# frozen_string_literal: true

# Asks the site to rebuild through the configured provider (Deploys).
class Deploys::TriggerJob < ApplicationJob
  queue_as :default

  def perform(scheduled_at, reason) = Deploys.trigger_now(scheduled_at, reason)
end
