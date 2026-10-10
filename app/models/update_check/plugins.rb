# frozen_string_literal: true

# Whether a plugin or theme has a newer release: the latest published release
# of the GitHub repository each came from (InstalledPlugins.repo), checked
# daily with the CMS's own (UpdateCheckJob) and kept in the "plugin_updates"
# setting so a page never waits on GitHub. Installing one is a PluginChange.
#
#   UpdateCheck::Plugins.check_now   # fetch and store; a plugin GitHub won't answer for keeps what it had
#   UpdateCheck::Plugins.available   # {"healing" => "0.3.0"}: those with a newer release than they run
module UpdateCheck::Plugins
  SETTING_KEY = "plugin_updates"

  module_function

  def check_now
    found = stored.dup
    InstalledPlugins.loaded.each_key do |name|
      repo = InstalledPlugins.repo(name) or next
      # One the directory lists updates to the release it vouches for.
      if (listed = PluginDirectory.find_by_repo(repo))
        found[name] = {"latest_version" => listed.version, "release_url" => "https://github.com/#{repo}/releases/tag/v#{listed.version}"}
        next
      end
      release = UpdateCheck::Github.new(repo: repo).get("releases/latest")
      found[name] = {"latest_version" => release["tag_name"].to_s.delete_prefix("v"), "release_url" => release["html_url"]}
    rescue StandardError => error
      Rails.logger.warn("[update_check] #{name}: #{error.class}: #{error.message}")
    end
    Setting.set(SETTING_KEY, found.slice(*InstalledPlugins.loaded.keys).merge("checked_at" => Time.current.iso8601))
  end

  def available
    stored.except("checked_at").filter_map do |name, release|
      latest = release["latest_version"].presence or next
      running = InstalledPlugins.versions[name] or next
      [name, latest] if Gem::Version.new(latest) > Gem::Version.new(running)
    rescue ArgumentError
      nil
    end.to_h
  end

  def latest_version(name) = available[name.to_s]
  def release_url(name) = stored.dig(name.to_s, "release_url").presence
  def checked_at = stored["checked_at"].presence&.then { Time.zone.parse(it) }

  def stored = Setting.get(SETTING_KEY)
  private_class_method :stored
end
