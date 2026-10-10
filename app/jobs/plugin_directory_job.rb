# frozen_string_literal: true

# Fetches the plugin directory (PluginDirectory), when Settings › Plugins
# finds it never was, or someone asks for it again.
class PluginDirectoryJob < ApplicationJob
  queue_as :default

  def perform = PluginDirectory.refresh
end
