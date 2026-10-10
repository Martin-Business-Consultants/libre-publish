# frozen_string_literal: true

# Every Settings page renders in the settings layout: its title across the
# top, the page in two thirds, and a sidebar in the other third (its Save box,
# when it has one, and the Settings sections).
class Settings::BaseController < ApplicationController
  layout "settings"

  private

  def settings_screen? = true

  # For what restarts or replaces the install (an update, a plugin's code),
  # which takes an admin, not just settings:write.
  def require_admin
    raise Authorization::Forbidden, Permissions::WILDCARD unless Current.user&.admin?
  end
end
