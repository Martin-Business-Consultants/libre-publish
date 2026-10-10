# frozen_string_literal: true

# Settings › Themes: the plugins that draw the website (Website.themes),
# which one does, and installing or updating one from GitHub. A theme is a
# plugin, so installing, updating and removing it are PluginChanges, as in
# Settings › Plugins, and switching it on and off is its plugin switch.
class Settings::ThemesController < Settings::BaseController
  requires_capability "settings:read", only: :index

  def index
    PluginChange.reconcile
    @themes = Website.themes.values.sort_by(&:name)
    @change = PluginChange.current
    @directory = PluginDirectory.themes
    PluginDirectoryJob.perform_later unless PluginDirectory.checked_at
  end
end
