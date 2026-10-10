# frozen_string_literal: true

# Plugins' actions (Cms::Plugins.on) hear every "<event>.cms" notification.
# Search engines hear about published changes (IndexNow).
Rails.application.config.after_initialize do
  Cms::Hooks.subscribe!
  IndexNow.subscribe!
end
