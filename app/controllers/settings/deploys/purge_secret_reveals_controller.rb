# frozen_string_literal: true

# The secret a site checks cache purges with (its CMS_WEBHOOK_SECRET), into
# Settings › Deploy's secret frame. Looking is audited.
class Settings::Deploys::PurgeSecretRevealsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    @secret = Frontend.purge_secret
    Event.record("settings.purge_secret_revealed")
    render layout: false
  end
end
