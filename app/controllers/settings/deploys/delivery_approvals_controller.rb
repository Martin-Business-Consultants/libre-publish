# frozen_string_literal: true

# Takes what the site's last build reported about how it renders and where
# it takes purges — the change a build can't make on its own
# (Frontend.record_build).
class Settings::Deploys::DeliveryApprovalsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  def create
    if Frontend.approve_delivery!
      redirect_to settings_deploy_path(anchor: "site"), notice: "Publishing now follows what the site reported"
    else
      redirect_to settings_deploy_path(anchor: "site"), alert: "Nothing is waiting for approval"
    end
  end
end
