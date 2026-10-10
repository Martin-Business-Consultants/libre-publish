# frozen_string_literal: true

require "json"

# The plugins installed from Settings › Plugins, loaded at boot
# (config/application.rb). They live in CMS_DATA_DIR/plugins, one directory
# per plugin, so they outlast deploys and core updates: each is a Rails engine
# with a gemspec at its root, a GitHub release put there by PluginChange.
# They aren't bundled, since Bundler freezes the Gemfile in production: a
# plugin's lib/ goes on the load path and it's required by name, so it may
# depend only on gems the core bundles. Its engine adds its migrations as a
# bundled one's does. A plugin of the same name in plugins/ or engines/ (a
# gem) wins. Not in Zeitwerk's lib/, so it loads once.
module InstalledPlugins
  extend self

  METADATA = ".cms-plugin.json"

  def directory
    root = File.expand_path("..", __dir__)
    Pathname(File.expand_path(ENV["CMS_DATA_DIR"].to_s.empty? ? "storage" : ENV["CMS_DATA_DIR"], root)).join("plugins")
  end

  # Every plugin directory, by its gem name, which is also its key.
  def present
    return {} unless directory.directory?

    directory.children.sort.filter_map do |path|
      next unless path.directory? && !path.basename.to_s.start_with?(".")

      gemspec = path.glob("*.gemspec").first or next
      [gemspec.basename(".gemspec").to_s, path]
    end.to_h
  end

  def loaded = @loaded ||= {}
  def failed = @failed ||= {}
  # The release each was at when this process booted; the directory may since hold another.
  def versions = @versions ||= {}

  # Off in tests, which cover the core and its bundled plugins, and with
  # CMS_INSTALLED_PLUGINS=off (to boot without a plugin that keeps the app
  # from starting).
  def load!
    return if ENV["RAILS_ENV"] == "test" || ENV["CMS_INSTALLED_PLUGINS"] == "off"

    present.each do |name, path|
      next if Gem.loaded_specs.key?(name)

      $LOAD_PATH.unshift path.join("lib").to_s
      require name
      loaded[name] = path
      versions[name] = metadata(name)["version"]
    rescue ScriptError, StandardError => error
      failed[name] = "#{error.class}: #{error.message}"
      warn "[plugins] #{name} didn't load: #{failed[name]}"
    end
  end

  # Where it came from and which release it is, written when it was installed.
  def metadata(name)
    path = (loaded[name] || present[name])&.join(METADATA)
    path&.exist? ? JSON.parse(path.read) : {}
  rescue JSON::ParserError
    {}
  end
end
