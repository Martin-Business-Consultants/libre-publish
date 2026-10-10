# frozen_string_literal: true

# Every Settings page renders in the settings layout: its title across the
# top, the page in two thirds, and a sidebar in the other third (its Save box,
# when it has one, and the Settings sections).
class Settings::BaseController < ApplicationController
  layout "settings"

  private

  def settings_screen? = true

  # Where installing, updating or removing a plugin goes back to: Settings ›
  # Themes when it was started there (from=themes), else Settings › Plugins.
  def plugins_page = (params[:from] == "themes") ? settings_themes_path : settings_plugins_path

  # For what restarts or replaces the install (an update, a plugin's code),
  # which takes an admin, not just settings:write.
  def require_admin
    raise Authorization::Forbidden, Permissions::WILDCARD unless Current.user&.admin?
  end
end
