# frozen_string_literal: true

# "Clear failed updates" on Settings › Plugins: takes the plugin and theme
# installs, updates and removals that failed (PluginChange) out of Recent
# changes, with what each kept of its restart (PluginChange#report). What
# succeeded, and one running, stay.
class Settings::Plugins::FailuresController < Settings::BaseController
  requires_capability "settings:write", only: :destroy

  before_action :require_admin, only: :destroy

  def destroy
    failed = PluginChange.where(status: "failed").to_a
    failed.each { FileUtils.rm_rf(it.report) }
    count = PluginChange.where(id: failed.map(&:id)).delete_all
    Event.record("plugins.failures_cleared", count: count)
    redirect_to plugins_page, notice: "Cleared #{helpers.pluralize(count, "failed change")}."
  end
end
