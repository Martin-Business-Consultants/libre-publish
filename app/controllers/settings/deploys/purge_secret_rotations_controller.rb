# frozen_string_literal: true

# A new purge secret: the old one stops verifying, so the site needs the new
# CMS_WEBHOOK_SECRET before the next purge.
class Settings::Deploys::PurgeSecretRotationsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    Frontend.rotate_purge_secret
    Event.record("settings.purge_secret_rotated")
    redirect_to settings_deploy_path(anchor: "site"), notice: "Purge secret rotated — give the site the new one"
  end
end
