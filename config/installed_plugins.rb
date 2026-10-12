# frozen_string_literal: true

require "json"

# Every plugin this install runs, loaded at boot (config/application.rb), one
# way whatever brought it: a Rails engine with a gemspec at its root, its
# lib/ put on the load path and required by name. Not through Bundler, so a
# plugin can be updated after the install's image was built (the lock file
# never changes) and may depend only on gems the core bundles.
#
# Plugins come from, most preferred first:
#
#   installed  CMS_DATA_DIR/plugins: installed or updated from Settings ›
#              Plugins (PluginChange), so they outlast deploys and updates
#   image      plugins/ and themes/: the default plugins and CMS_PLUGINS
#              (bin/fetch-plugins), the theme (bin/fetch-theme), a checkout's
#   reference  engines/: the reference plugin, in development and test only
#
# For each name the newest version runs, and on a tie the most preferred
# source, so an update installed from the admin wins over the image's copy
# until a newer image or release brings a newer one. Each records where it
# came from (.cms-plugin.json: its GitHub repository, ref and version), which
# is how Settings › Plugins updates it. Not in Zeitwerk's lib/, so it loads
# once.
module InstalledPlugins
  extend self

  METADATA = ".cms-plugin.json"

  # Plugins whose work the core now does itself, with the version that took
  # it in: an install that still has one (default_plugins.yml before then, or
  # the data directory) boots without it rather than with two of everything.
  ABSORBED = {"media" => "1.12.0"}.freeze
  ROOT = Pathname(File.expand_path("..", __dir__))

  # CMS_DATA_DIR/plugins, where Settings › Plugins installs.
  def directory
    Pathname(File.expand_path(ENV["CMS_DATA_DIR"].to_s.empty? ? "storage" : ENV["CMS_DATA_DIR"], ROOT)).join("plugins")
  end

  # The plugins installed in the data directory, by name.
  def present = plugins_in(directory).to_h { [it[:name], it[:path]] }

  # Where plugins come from, most preferred first. A test run loads the
  # image's and the reference plugin, never the data directory's;
  # CMS_INSTALLED_PLUGINS=off boots without the data directory's (to start an
  # install one of them keeps from starting).
  def sources(env = ENV)
    rails_env = env["RAILS_ENV"].to_s.empty? ? "development" : env["RAILS_ENV"]
    list = []
    list << [:installed, directory] unless rails_env == "test" || env["CMS_INSTALLED_PLUGINS"] == "off"
    list << [:image, ROOT.join("plugins")] << [:image, ROOT.join("themes")]
    list << [:reference, ROOT.join("engines")] if %w[development test].include?(rails_env)
    list
  end

  # Every copy of every plugin there is: name => [{path:, version:, source:}],
  # most preferred source first.
  def available(env = ENV)
    sources(env).each_with_object({}) do |(source, root), found|
      plugins_in(root).each { (found[it[:name]] ||= []) << it.merge(source: source) }
    end
  end

  # The copy each name runs: the newest version, and on a tie the most
  # preferred source.
  def chosen(env = ENV)
    available(env).transform_values do |copies|
      copies.each_with_index.max_by { |copy, index| [Gem::Version.new(copy[:version] || "0"), -index] }.first
    end
  end

  def loaded = @loaded ||= {}
  def failed = @failed ||= {}
  # The version each was at when this process booted; its directory may since hold another.
  def versions = @versions ||= {}
  # Where each that loaded came from: :installed, :image or :reference.
  def origins = @origins ||= {}
  # Those left unloaded because the core does their work now (ABSORBED).
  def absorbed = @absorbed ||= {}

  # One installed from Settings › Plugins that can't run here: it never
  # registers with the CMS, so booting it would stop the install starting
  # (a Runwell plugin's engine calls Runwell::Plugins). It's left unloaded,
  # with why, for Settings › Plugins to offer its removal.
  Unloaded = Data.define(:key, :name)

  def foreign?(path)
    code = path.glob("{lib,config}/**/*.rb").map { it.read rescue "" }
    return false if code.any? { it.include?("Cms::Plugins.register") }

    code.any? { it.include?("Runwell::Plugins") } ? "it's a Runwell plugin" : "it never registers with the CMS"
  end

  def load!
    chosen.each do |name, copy|
      next if Gem.loaded_specs.key?(name) # still in a Gemfile as a gem: Bundler loaded it
      next absorbed[name] = copy[:path] if ABSORBED.key?(name)
      if copy[:source] == :installed && (reason = foreign?(copy[:path]))
        failed[name] = "it isn't a CMS plugin: #{reason}, so it's left unloaded. Remove it."
        warn "[plugins] #{name} left unloaded: #{failed[name]}"
        next
      end

      $LOAD_PATH.unshift copy[:path].join("lib").to_s
      require name
      loaded[name] = copy[:path]
      versions[name] = copy[:version]
      origins[name] = copy[:source]
    rescue ScriptError, StandardError => error
      failed[name] = "#{error.class}: #{error.message}"
      warn "[plugins] #{name} didn't load: #{failed[name]}"
    end
  end

  # Where it came from and which release it is: written when it was
  # installed (PluginChange) or fetched into the image (bin/fetch-plugins,
  # bin/fetch-theme).
  def metadata(name)
    path = (loaded[name] || present[name])&.join(METADATA)
    path&.exist? ? JSON.parse(path.read) : {}
  rescue JSON::ParserError
    {}
  end

  # Its GitHub repository (owner/name), where its updates come from: from its
  # metadata, or a checkout's git remote. Nil when nothing says.
  def repo(name)
    metadata(name)["repo"].presence || git_remote_repo(loaded[name] || present[name])
  end

  # The plugins under one root: [{name:, path:, version:}].
  def plugins_in(root)
    return [] unless root.directory?

    root.children.sort.filter_map do |path|
      next unless path.directory? && !path.basename.to_s.start_with?(".")

      gemspec = path.glob("*.gemspec").first or next
      {name: gemspec.basename(".gemspec").to_s, path: path, version: version_of(gemspec)}
    end
  end

  # A gemspec's version, read rather than run: `spec.version = "1.2.0"`, or
  # the `VERSION = "1.2.0"` of a lib/**/version.rb it names instead.
  def version_of(gemspec)
    quoted = /["']([^"']+)["']/
    gemspec.read[/\.version\s*=\s*#{quoted}/, 1] ||
      gemspec.dirname.glob("lib/**/version.rb").lazy.filter_map { it.read[/VERSION\s*=\s*#{quoted}/, 1] }.first
  end

  def git_remote_repo(path)
    return unless path && path.join(".git").exist?

    url = IO.popen(["git", "-C", path.to_s, "remote", "get-url", "origin"], err: File::NULL, &:read).to_s.strip
    url[%r{github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?\z}, 1]
  end
end
