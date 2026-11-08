# frozen_string_literal: true

# Every night: each enabled plugin's nightly task (Cms::Plugins.run_nightly).
class PluginsNightlyJob < ApplicationJob
  queue_as :default

  def perform
    Cms::Plugins.run_nightly
  end
end
