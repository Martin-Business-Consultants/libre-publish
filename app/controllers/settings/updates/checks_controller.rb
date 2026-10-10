# frozen_string_literal: true

# "Check now" on Settings › Updates: asks GitHub for the newest release
# rather than waiting for the daily check, for the CMS and for its plugins
# and themes (the plugin directory first). Only reads GitHub, so anyone who
# can open the page can ask.
class Settings::Updates::ChecksController < Settings::BaseController
  requires_capability "settings:read", only: :create

  def create
    UpdateCheck.check_now!
    PluginDirectory.refresh
    UpdateCheck::Plugins.check_now
    plugins = UpdateCheck::Plugins.available
    also = plugins.any? ? " Updates for #{plugins.keys.to_sentence} are in Settings › Plugins and Themes." : ""

    if UpdateCheck.update_available?
      redirect_to settings_updates_path, notice: "CMS #{UpdateCheck.latest_version} is out. This install runs #{Cms::VERSION}.#{also}"
    else
      redirect_to settings_updates_path, notice: "CMS #{Cms::VERSION} is the newest release.#{also}"
    end
  rescue UpdateCheck::Github::Error => error
    redirect_to settings_updates_path, alert: error.message
  end
end
