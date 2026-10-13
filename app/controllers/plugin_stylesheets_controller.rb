# frozen_string_literal: true

# GET /plugin-styles/<name>.css — a plugin's stylesheet straight from its own
# files, for when it isn't among the compiled assets: a plugin installed or
# updated from Settings › Plugins on an image whose assets were compiled
# without it, before (or instead of) the compile that adds it
# (config/initializers/installed_plugins.rb). The admin links here only then
# (ApplicationHelper#plugin_stylesheet_tag), so a plugin's screens keep their
# styles whatever happened to the compile. Only stylesheets a plugin
# registered (Cms::Plugins.stylesheet) are served; nothing in them is secret.
class PluginStylesheetsController < ApplicationController
  skip_authorization
  skip_before_action :authenticate

  def show
    name = params[:name].to_s
    return head(:not_found) unless Cms::Plugins.stylesheets.values.flatten.include?(name)

    asset = Rails.application.assets.load_path.find("#{name}.css") or return head(:not_found)
    expires_in 5.minutes, public: true
    render plain: asset.compiled_content, content_type: "text/css" if stale?(etag: asset.digest, public: true)
  end
end
