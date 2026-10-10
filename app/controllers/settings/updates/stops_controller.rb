# frozen_string_literal: true

# "Stop this update" on Settings › Updates: gives up on an update that's
# running (Upgrade#stop!), when it's gone quiet and nobody can reach the
# server to see why. The version running keeps running; the update can be
# started again. Starting one takes an admin, so stopping one does too.
class Settings::Updates::StopsController < Settings::BaseController
  requires_capability "settings:write", only: :create

  before_action :require_admin, only: :create

  def create
    if (upgrade = Upgrade.current)
      upgrade.stop!(by: Current.user)
      redirect_to settings_updates_path, notice: "Stopped the update to #{upgrade.to_version}. #{Cms::VERSION} keeps running; you can start it again."
    else
      redirect_to settings_updates_path, notice: "No update is running."
    end
  end
end
