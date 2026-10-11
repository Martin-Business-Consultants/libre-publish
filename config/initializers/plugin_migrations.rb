# frozen_string_literal: true

# db/schema.rb is the core's. Loading it into a new database (db:prepare on a
# fresh install, a test database) records every migration Rails can find
# that's older than the schema as run, an installed plugin's too, though its
# tables aren't in the schema: its migrations would then never run, and the
# plugin would start without its tables. So after a load, only the core's own
# migrations (db/migrate, and the reference plugin's in engines/, whose
# tables the schema has) stay recorded; a plugin's run on top, as they do
# when it's installed later.
module PluginMigrations
  CORE_PATHS = [Rails.root.join("db/migrate").to_s, Rails.root.join("engines").to_s].freeze

  def assume_migrated_upto_version(version)
    before = pool.migration_context.get_all_versions
    super

    plugins = pool.migration_context.migrations.reject { |migration| core?(migration.filename) }.map(&:version) - before
    return if plugins.empty?

    execute "DELETE FROM #{quote_table_name(pool.schema_migration.table_name)} WHERE version IN (#{plugins.map { quote(it.to_s) }.join(", ")})"
  end

  private

  def core?(filename)
    path = File.expand_path(filename, Rails.root)
    CORE_PATHS.any? { path.start_with?("#{it}/") }
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::AbstractAdapter.prepend(PluginMigrations)
end
