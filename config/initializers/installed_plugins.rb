# frozen_string_literal: true

# Plugins (InstalledPlugins) own tables named for their key, which stay out
# of the core's schema.rb: a new install loads the core alone, and each
# plugin migrates its own tables when it's installed.
Rails.application.config.after_initialize do
  # Every plugin's but the reference one's (engines/, whose tables the test
  # database is loaded with): from the data directory, or the image's.
  keys = InstalledPlugins.present.keys + InstalledPlugins.origins.reject { |_, origin| origin == :reference }.keys
  prefixes = keys.uniq.map { "#{it}_" }
  ActiveRecord::SchemaDumper.ignore_tables |= [/\A(?:#{prefixes.map { Regexp.escape(it) }.join("|")})/] if prefixes.any?

  # A plugin installed from Settings › Plugins brings stylesheets the image
  # never compiled, and one updated there brings new ones under the old
  # names. Production serves only compiled assets, so compile once more when
  # any of a plugin's are missing or compiled from an older version (the
  # manifest's digest isn't the file's), before the first request reads the
  # manifest. Checking the name alone kept an updated plugin on its old
  # stylesheet: Forms 1.7's screens, redrawn in the admin's CSS, came up
  # unstyled.
  if Rails.env.production? && InstalledPlugins.loaded.any?
    assets = Rails.application.assets
    manifest = assets.config.manifest_path
    compiled = manifest.exist? ? Propshaft::Manifest.from_path(manifest) : Propshaft::Manifest.new
    roots = InstalledPlugins.loaded.values.map { it.realpath.to_s }
    stale = assets.load_path.assets.any? do |asset|
      asset.path.realpath.to_s.start_with?(*roots) && compiled[asset.logical_path.to_s]&.digested_path.to_s != asset.digested_path.to_s
    end

    begin
      assets.processor.process if stale
    rescue => error
      # Logged, never fatal: the admin links a stylesheet it can't find from
      # the plugin's own files (ApplicationHelper#plugin_stylesheet_tag).
      Rails.logger.warn "[plugins] couldn't compile plugin assets: #{error.class}: #{error.message}"
    end
  end
end
