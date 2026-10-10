# frozen_string_literal: true

# Installs a plugin on this server from its GitHub repository's latest
# release (PluginChange). It runs code on the server, so it takes an admin.
class Settings::Plugins::InstallationsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  before_action :require_admin

  def create
    change = PluginChange.install(params[:repo], by: Current.user)
    redirect_to settings_plugins_path, notice: "#{change.summary}. The CMS restarts when it's done; then switch it on here."
  rescue PluginChange::Refused, ActiveRecord::RecordInvalid => error
    redirect_to settings_plugins_path, alert: error.message
  end
end
