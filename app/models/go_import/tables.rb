# frozen_string_literal: true

require "sqlite3"

# A new database for this install, built beside it rather than adopted from
# the Go core: the Go core's schema is this core's tables (a subset, by the
# same names and columns) plus its own, and it keeps no schema_migrations
# (PRAGMA user_version), so the Go file can't simply be migrated.
#
# The new file gets this install's schema exactly as its own database has it
# (every table, index and trigger, plugins' included, and the record of the
# migrations that made them), then each table both have is copied across,
# ids kept, by the columns both have. What only the Go core keeps is counted
# and left behind: browser sessions, edit locks, autosaves, the webhook
# outbox, its pending revisions, its plugins' registry (their data is
# GoImport::Forms's to read).
class GoImport::Tables
  # The Go core's tables this one has no use for, and why they're left.
  LEFT_BEHIND = {
    "admin_sessions" => "signed in to the old site", "sessions" => "signed in to the old site",
    "device_authorizations" => "device sign-ins in progress", "account_tokens" => "password reset and email links",
    "edit_locks" => "edit locks", "autosaves" => "unsaved edits", "user_preferences" => "admin preferences",
    "webhook_outbox" => "webhook deliveries not yet made", "revisions" => "changes waiting for review",
    "rails_revisions" => "the Rails core's old pending changes", "plugins" => "the Go core's plugin registry"
  }.freeze
  # Read by GoImport::Forms, which says what became of them.
  PLUGIN_RECORDS = "plugin_kv"
  # Rebuilt here rather than copied (the search index, after the import).
  OWN = %w[schema_migrations ar_internal_metadata record_documents].freeze

  def initialize(db, target:, report:)
    @db = db
    @target = target
    @report = report
  end

  # this install's schema into the empty database.
  def create_schema
    rows = @target.select_rows("SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid")
    raise GoImport::Error, "This install's database has no tables yet: run bin/rails db:prepare first" if rows.none? { it[1] == "users" }

    virtual = rows.select { it[2].match?(/\ACREATE VIRTUAL TABLE/i) }.map { it[1] }
    shadow = ->(name) { virtual.any? { name.start_with?("#{it}_") } }
    %w[table index trigger view].each do |type|
      rows.each { |row_type, name, sql| @db.execute(sql) if row_type == type && !shadow.(name) }
    end
    %w[schema_migrations ar_internal_metadata].each { copy_own(it) }
  end

  def copy
    @db.execute("PRAGMA foreign_keys = OFF")
    go_tables = tables("go")
    mine = tables("main")
    (go_tables - mine - [PLUGIN_RECORDS]).each { |table| @report.skipped[table] = count("go", table) }
    (go_tables & mine).each { copy_table(it) unless OWN.include?(it) || LEFT_BEHIND.key?(it) }
    LEFT_BEHIND.each_key { |table| @report.skipped[table] = count("go", table) if go_tables.include?(table) }
    @report.skipped.delete_if { |_, n| n.zero? }
    dangling
  end

  def tables(schema)
    @db.execute("SELECT name FROM #{schema}.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").flatten
  end

  def columns(schema, table)
    @db.execute("SELECT name FROM pragma_table_info(?, ?)", [table, schema]).flatten
  end

  def count(schema, table) = @db.get_first_value("SELECT COUNT(*) FROM #{schema}.#{quote(table)}").to_i

  private

  def copy_own(table)
    columns = @target.columns(table).map(&:name)
    @target.select_rows("SELECT #{columns.map { quote(it) }.join(", ")} FROM #{quote(table)}").each do |row|
      @db.execute("INSERT INTO #{quote(table)} (#{columns.map { quote(it) }.join(", ")}) VALUES (#{(["?"] * columns.size).join(", ")})", row)
    end
  end

  # All at once, or row by row when a row breaks one of this core's
  # constraints (it keeps one personal token a person, say): each one refused
  # is named.
  def copy_table(table)
    shared = columns("go", table) & columns("main", table)
    list = shared.map { quote(it) }.join(", ")
    order = (table == "api_tokens") ? "COALESCE(last_used_at, created_at) DESC, id DESC" : "rowid"
    begin
      @db.transaction { @db.execute("INSERT INTO main.#{quote(table)} (#{list}) SELECT #{list} FROM go.#{quote(table)} ORDER BY #{order}") }
    rescue SQLite3::ConstraintException
      @db.execute("SELECT #{list} FROM go.#{quote(table)} ORDER BY #{order}").each do |row|
        @db.execute("INSERT INTO main.#{quote(table)} (#{list}) VALUES (#{(["?"] * shared.size).join(", ")})", row)
      rescue SQLite3::ConstraintException => e
        @report.not_carry("#{table} ##{row[shared.index("id")] if shared.include?("id")}: #{refusal(table, e)}")
      end
    end
    dropped = columns("go", table) - shared
    dropped_used = dropped.select { @db.get_first_value("SELECT COUNT(*) FROM go.#{quote(table)} WHERE #{quote(it)} IS NOT NULL AND #{quote(it)} NOT IN ('', '[]', '{}', 0)").to_i.positive? }
    @report.not_carry("#{table}: #{dropped_used.join(", ")} (this core has no such column)") if dropped_used.any? && !quiet_columns(table, dropped_used)
    @report.count_table(table, source: count("go", table), carried: count("main", table))
  end

  # Columns whose loss the import reports in its own words (webhooks), or
  # that only kept history (a delivery's event, a token's label).
  def quiet_columns(table, columns)
    (columns - {"webhooks" => %w[kind body_map testing_url], "webhook_deliveries" => %w[event_data test], "api_tokens" => %w[label]}.fetch(table, [])).empty?
  end

  def refusal(table, error)
    if table == "api_tokens" && error.message.include?("user_id")
      "a second personal token for the same person (this core keeps one each; the most recently used is kept)"
    else
      error.message
    end
  end

  # A row whose reference the Go database didn't keep: the reference
  # cleared where it may be empty, the row left out where it may not.
  def dangling
    @db.execute("PRAGMA foreign_key_check").each do |table, rowid, parent, fk|
      column = @db.execute("SELECT \"from\" FROM pragma_foreign_key_list(?) WHERE id = ?", [table, fk]).first&.first
      nullable = @db.execute("SELECT \"notnull\" FROM pragma_table_info(?) WHERE name = ?", [table, column]).first&.first.to_i.zero?
      if column && nullable
        @db.execute("UPDATE #{quote(table)} SET #{quote(column)} = NULL WHERE rowid = ?", [rowid])
      else
        @db.execute("DELETE FROM #{quote(table)} WHERE rowid = ?", [rowid])
        @report.not_carry("#{table} ##{rowid}: its #{parent} is gone from the backup")
        @report.tables[table][:carried] -= 1 if @report.tables[table]
      end
    end
  end

  def quote(name) = %("#{name.to_s.gsub('"', '""')}")
end
