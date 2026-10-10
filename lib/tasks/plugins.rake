# frozen_string_literal: true

# Installed plugins live in plugins/, one directory per plugin, each a gem
# with a gemspec the Gemfile picks up. Installing clones a git repository
# there, bundles, migrates and asks Puma to restart. Bundled plugins
# (engines/) ship with the core and are never touched here. docs/plugins.md.
namespace :plugins do
  desc "Run the first-time setup of every plugin that's on but was never set up here (role defaults, block types)"
  task settle: :environment do
    Cms::Plugins.settle!.each do |key, granted|
      granted.each { |role, capabilities| puts "#{key}: #{role} gets #{capabilities.join(", ")}" }
    end
  end

  desc "List every plugin: bundled and installed, version, on or off"
  task list: :environment do
    Cms::Plugins.manifests.values.sort_by(&:name).each do |plugin|
      state = Cms::Plugins.enabled?(plugin.key) ? "on " : "off"
      source = plugin.bundled ? "bundled" : "plugins/#{plugin.key}"
      notes = []
      notes << "needs CMS #{plugin.requires}; this is #{Cms::VERSION}" unless plugin.compatible?
      missing = Cms::Plugins.missing_dependencies(plugin.key)
      notes << "needs #{missing.join(", ")} on" if missing.any?
      note = notes.any? ? "  (#{notes.join("; ")})" : ""
      puts "#{state}  #{plugin.name.ljust(24)} #{plugin.version.ljust(8)} #{source}#{note}"
    end
  end

  desc 'Install a plugin from a git URL, optionally at a tag or branch: bin/rails "plugins:install[https://github.com/org/cms-thing,v1.2.0]"'
  task :install, [:url, :ref] do |_task, args|
    url = args[:url].presence or abort 'Usage: bin/rails "plugins:install[https://github.com/org/plugin]"'
    name = File.basename(url.sub(/\.git\z/, ""))
    directory = plugins_directory.join(name)
    abort "#{directory} already exists. To update it: bin/rails \"plugins:update[#{name}]\"" if directory.exist?

    clone_plugin(url, args[:ref].presence, directory)
    if Dir.glob(directory.join("*.gemspec")).none?
      directory.rmtree
      abort "#{name} isn't a CMS plugin: no gemspec. Nothing was installed."
    end

    apply_plugin_changes!
    puts "\nInstalled #{name}. Switch it on in Settings › Plugins."
  end

  # The plugins every install starts with (config/default_plugins.yml), each
  # installed unless a plugin by that name is already there. bin/setup and
  # bin/install run it; running it again changes nothing.
  desc "Install the default plugins that aren't installed yet (config/default_plugins.yml)"
  task :install_defaults do
    missing = default_plugins.reject { |name, _| installed_plugin?(name) }
    if missing.empty?
      puts "The default plugins are installed: #{default_plugins.keys.join(", ")}."
      next
    end

    missing.each do |name, source|
      url, ref = source.split("#", 2)
      clone_plugin(url, ref, plugins_directory.join(name))
    end
    apply_plugin_changes!
    puts "\nInstalled #{missing.keys.join(", ")}. Switch them on in Settings › Plugins if they aren't already."
  end

  desc 'Pull the latest version of an installed plugin (all of them with no name): bin/rails "plugins:update[name]"'
  task :update, [:name] do |_task, args|
    directories = args[:name].present? ? [plugins_directory.join(args[:name])] : plugins_directory.glob("*").select(&:directory?)
    abort "Nothing installed in #{plugins_directory}" if directories.none?

    directories.each do |directory|
      abort "No plugin at #{directory}" unless directory.join(".git").exist?
      puts "== #{directory.basename} =="
      # A plugin installed at a commit (default_plugins.yml pins them) stays
      # there until it's pinned elsewhere.
      if system("git", "-C", directory.to_s, "symbolic-ref", "-q", "HEAD", out: File::NULL)
        run! "git", "-C", directory.to_s, "pull", "--ff-only"
      else
        puts "Pinned at #{`git -C #{directory} rev-parse --short HEAD`.strip}; not updated."
      end
    end
    apply_plugin_changes!
  end

  desc 'Remove an installed plugin\'s code (its tables stay): bin/rails "plugins:remove[name]"'
  task :remove, [:name] do |_task, args|
    directory = plugins_directory.join(args[:name].to_s)
    abort "No plugin at #{directory}" unless args[:name].present? && directory.join(".git").exist?

    directory.rmtree
    apply_plugin_changes!
    puts "\nRemoved #{args[:name]}. Its tables are still in the database, so reinstalling brings the data back."
  end

  def plugins_directory = Rails.root.join("plugins")

  # Clones a plugin at `ref`: a tag or branch, or a commit (40 hex digits),
  # which is how default_plugins.yml pins the defaults.
  def clone_plugin(url, ref, directory)
    if ref&.match?(/\A\h{40}\z/)
      run! "git", "clone", "--quiet", url, directory.to_s
      run! "git", "-C", directory.to_s, "checkout", "--quiet", ref
    else
      run! "git", "clone", "--depth", "1", *(["--branch", ref] if ref), url, directory.to_s
    end
  end

  def default_plugins
    YAML.safe_load_file(Rails.root.join("config/default_plugins.yml")) || {}
  end

  # A plugin of that name is in plugins/, whatever its directory is called.
  def installed_plugin?(name)
    plugins_directory.glob("*/#{name}.gemspec").any? || plugins_directory.join(name).exist?
  end

  def run!(*command)
    puts "  $ #{command.join(" ")}"
    system(*command, exception: true)
  end

  # The Gemfile changed, so bundle and migrate in fresh processes, on the
  # environment this one started with (an install's own Bundler settings
  # kept). Puma's tmp_restart plugin picks up the touch; a Docker install
  # rebuilds its image instead (the Dockerfile copies plugins/ in before
  # bundling).
  def apply_plugin_changes!
    Bundler.with_original_env do
      run! "bundle", "install"
      run! "bin/rails", "db:migrate"
      run! "bin/rails", "assets:precompile" if ENV["RAILS_ENV"] == "production"
    end
    FileUtils.touch Rails.root.join("tmp/restart.txt")
  end
end

# A plugin reaches a site in several ways — bin/setup, `plugins:install`,
# Settings › Plugins, a Docker image built with CMS_PLUGINS — and every one
# migrates (or prepares) after it, in a process that has the plugin loaded.
# So set up whatever is on but never was, there.
%w[db:migrate db:prepare].each do |name|
  Rake::Task[name].enhance { Rake::Task["plugins:settle"].invoke } if Rake::Task.task_defined?(name)
end
