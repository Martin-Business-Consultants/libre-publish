# frozen_string_literal: true

# Appearance — light, dark or follow the system — is a section of Settings ›
# Branding. It's stored in the browser (localStorage "appearance"), so
# there's nothing to save and nothing to gate.
class Settings::AppearancesController < Settings::BaseController
  skip_authorization

  def show
    redirect_to settings_branding_path(anchor: "appearance")
  end
end
