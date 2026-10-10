# frozen_string_literal: true

# Settings › Plugins: what this install adds to the core (engines/, plugins/
# and those installed here, Cms::Plugins), whether each is on and why one
# can't be; installing one from GitHub, and every install, update and removal
# with how it went (PluginChange). Removing one (destroy) takes its code off
# the server and keeps its data.
class Settings::PluginsController < Settings::BaseController
  requires_capability "settings:read", only: [:index, :show]
  requires_capability "settings:write", only: :destroy

  before_action :set_plugin, only: :show
  before_action :require_admin, only: :destroy

  def index
    PluginChange.reconcile
    @plugins = Cms::Plugins.manifests.values.sort_by(&:name)
    @change = PluginChange.current
    @changes = PluginChange.ordered.includes(:requested_by).limit(10)
  end

  def show
  end

  def destroy
    change = PluginChange.remove(params[:key], by: Current.user)
    redirect_to settings_plugins_path, notice: "#{change.summary}. The CMS restarts when it's done; this page shows how it went."
  rescue PluginChange::Refused, ActiveRecord::RecordInvalid => error
    redirect_to settings_plugins_path, alert: error.message
  end

  private

  def set_plugin
    @plugin = Cms::Plugins.manifests[params[:key].to_s.to_sym] or raise ActiveRecord::RecordNotFound
  end
end
