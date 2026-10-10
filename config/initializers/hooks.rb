# frozen_string_literal: true

# Plugins' actions (Cms::Plugins.on) hear every "<event>.cms" notification.
Rails.application.config.after_initialize { Cms::Hooks.subscribe! }
