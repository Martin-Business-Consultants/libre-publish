# frozen_string_literal: true

# "Clear failed updates" on Settings › Updates: takes the CMS updates that
# failed out of Past updates, once someone has read why. What succeeded, and
# one running, stay. Starting an update takes an admin, so clearing them does.
class Settings::Updates::FailuresController < Settings::BaseController
  requires_capability "settings:write", only: :destroy

  before_action :require_admin, only: :destroy

  def destroy
    count = Upgrade.where(status: "failed").delete_all
    Event.record("updates.failures_cleared", count: count)
    redirect_to settings_updates_path, notice: "Cleared #{helpers.pluralize(count, "failed update")}."
  end
end
