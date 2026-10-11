# frozen_string_literal: true

# Settings › History: every change to the settings people edit
# (SettingVersion: General, Branding, Search, Forms, Email delivery), newest
# first, each comparable with now and restorable. Restoring takes
# settings:write; a secret is never kept or put back.
class Settings::HistoriesController < Settings::BaseController
  requires_capability "settings:read",  only: [:index, :show]
  requires_capability "settings:write", only: :restore

  def index
    scope = SettingVersion.newest_first.includes(:author, :setting)
    @key = params[:key].presence_in(SettingVersion::VERSIONED.keys)
    scope = scope.where(key: @key) if @key
    @versions = paginate(scope)
  end

  def show
    @version = SettingVersion.find(params[:id])
  end

  def restore
    version = SettingVersion.find(params[:id])
    restored = version.snapshot["data"]
    Setting.changing(version.key) { it.data = restored }
    Event.record("settings.restored", key: version.key, version_id: version.id)
    redirect_to settings_history_path(version), notice: "#{version.label} restored to that version"
  end
end
