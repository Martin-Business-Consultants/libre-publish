# frozen_string_literal: true

# "Restore this version" in Settings › History. Takes settings:write; a
# secret is never kept or put back (SettingVersion#restore).
class Settings::Histories::RestorationsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    version = SettingVersion.find(params[:history_id])
    version.restore
    redirect_to settings_history_path(version), notice: "#{version.label} restored to that version"
  end
end
