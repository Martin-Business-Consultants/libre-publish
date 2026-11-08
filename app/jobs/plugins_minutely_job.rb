# frozen_string_literal: true

# Every minute: each enabled plugin's minutely tasks that are due
# (Cms::Plugins.run_minutely).
class PluginsMinutelyJob < ApplicationJob
  queue_as :default

  def perform(at: Time.current)
    Cms::Plugins.run_minutely(at)
  end
end
