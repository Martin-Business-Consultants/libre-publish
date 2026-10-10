# frozen_string_literal: true

# A plugin's Update button: its repository's latest release, in place of the
# one installed (PluginChange). Plugins update only this way, never along with
# the CMS.
class Settings::Plugins::UpgradesController < Settings::BaseController
  requires_capability "settings:write", only: :create

  before_action :require_admin

  def create
    change = PluginChange.update_plugin(params[:plugin_key], by: Current.user)
    redirect_to settings_plugins_path, notice: "#{change.summary}. The CMS restarts when it's done; this page shows how it went."
  rescue PluginChange::Refused, ActiveRecord::RecordInvalid => error
    redirect_to settings_plugins_path, alert: error.message
  end
end
