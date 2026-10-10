# frozen_string_literal: true

# For a plugin's controllers: its pages and API are 404 while it's switched
# off, before authentication or authorization get a say.
#
#   class Hello::GreetingsController < ApplicationController
#     include PluginGated
#     plugin :hello
#   end
module PluginGated
  extend ActiveSupport::Concern

  included do
    # Whose pages these are: the layout loads that plugin's stylesheet
    # (ApplicationHelper#page_plugins).
    class_attribute :plugin_key, instance_writer: false
  end

  class_methods do
    def plugin(key)
      self.plugin_key = key.to_sym
      prepend_before_action { head :not_found unless Cms::Plugins.enabled?(key) }
    end
  end
end
