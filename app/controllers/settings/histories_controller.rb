# frozen_string_literal: true

# Settings › History: every change to the settings people edit
# (SettingVersion: General, Branding, Search, Forms, Email delivery), newest
# first, each comparable with now and restorable
# (Settings::Histories::RestorationsController).
class Settings::HistoriesController < Settings::BaseController
  requires_capability "settings:read", only: [:index, :show]

  def index
    scope = SettingVersion.newest_first.includes(:author, :setting)
    @key = params[:key].presence_in(SettingVersion::VERSIONED.keys)
    scope = scope.where(key: @key) if @key
    @versions = paginate(scope)
  end

  def show
    @version = SettingVersion.find(params[:id])
  end
end
