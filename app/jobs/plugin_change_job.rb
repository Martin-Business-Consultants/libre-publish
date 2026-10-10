# frozen_string_literal: true

# Installs, updates or removes a plugin (PluginChange) away from the request
# that asked.
class PluginChangeJob < ApplicationJob
  def perform(change)
    change.perform if change.running?
  end
end
