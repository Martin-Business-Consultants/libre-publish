# frozen_string_literal: true

# Plugins installed from Settings › Plugins (InstalledPlugins) own tables
# named for their key, which stay out of the core's schema.rb: a new install
# loads the core alone, and each plugin migrates its own tables when it's
# installed.
Rails.application.config.after_initialize do
  prefixes = InstalledPlugins.present.keys.map { "#{it}_" }
  ActiveRecord::SchemaDumper.ignore_tables |= [/\A(?:#{prefixes.map { Regexp.escape(it) }.join("|")})/] if prefixes.any?

  # A plugin installed from Settings › Plugins brings stylesheets the image
  # never compiled. Production serves only compiled assets, so compile once
  # more when any of a plugin's are missing, before the first request reads
  # the manifest.
  if Rails.env.production? && InstalledPlugins.loaded.any?
    assets = Rails.application.assets
    manifest = assets.config.manifest_path
    compiled = manifest.exist? ? JSON.parse(manifest.read).keys : []
    roots = InstalledPlugins.loaded.values.map { it.realpath.to_s }
    missing = assets.load_path.assets.any? { |asset| asset.path.to_s.start_with?(*roots) && !compiled.include?(asset.logical_path.to_s) }

    begin
      assets.processor.process if missing
    rescue => error
      # Logged, never fatal: the admin leaves out a stylesheet it can't find
      # (ApplicationHelper#app_stylesheet_tags).
      Rails.logger.warn "[plugins] couldn't compile plugin assets: #{error.class}: #{error.message}"
    end
  end
end
