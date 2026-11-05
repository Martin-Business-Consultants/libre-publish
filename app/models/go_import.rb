# frozen_string_literal: true

require "fileutils"
require "sqlite3"

# Moves a site from the Go core (librepublishgo) into this install, replacing
# the site that's here: bin/rails "cms:import[PATH]", docs/import.md. PATH is
# the Go core's backup (Tools › Backup there, GET /api/tools/backup) or a
# directory holding one unpacked, or its data directory.
#
#   1. Unpacked into tmp/go_import/<time>/ (GoImport::Archive: only what a
#      backup holds, nothing outside it, within size limits) and checked:
#      SQLite's quick_check, and the tables a site has.
#   2. A new database is built beside it with this install's own schema
#      (GoImport::Tables), every table the two cores share copied in with
#      its ids, then brought onto this core's terms: rich text and file
#      addresses (GoImport::Content), the forms (GoImport::Forms), the sealed
#      secrets opened with the old key and kept as this core keeps them
#      (GoImport::Secrets), the files' blobs pointed at this install's
#      storage. Nothing outside tmp/ has changed: a dry run stops here, and
#      prints the report (GoImport::Report).
#   3. Refused when the install has users, unless force; refused when a key
#      was given and it opens none of the backup's secrets.
#   4. The install's database moves aside (production.sqlite3.before-import-
#      <time>) and the new one takes its place; each file is copied to this
#      install's storage and checked against its checksum; the search index
#      is rebuilt; site_backup.imported goes in the audit log. What the Go
#      plugins kept that no table here takes is written beside the database
#      as go-plugins-<time>.json.
#
# Everyone is signed out (the Go core's sessions aren't carried). People keep
# their passwords, roles and tokens (by digest).
class GoImport
  class Error < StandardError; end

  # The Go core's schema (PRAGMA user_version) this import was made for (v2.10).
  SCHEMA_VERSION = 1

  attr_reader :report

  # Whether path is the Go core's backup rather than the Rails core's.
  def self.backup?(path) = Archive.go?(path)

  # secret_keys: what the old install's key may be: its secret.key's contents
  # (SECRET_KEY_FILE) or the SECRET_KEY it ran with. A backup that includes
  # its secret.key needs neither.
  def initialize(source, secret_keys: [], dry_run: false, force: false, out: $stdout)
    @source = Pathname(source.to_s).expand_path
    @secret_keys = Array(secret_keys).compact_blank
    @dry_run = dry_run
    @force = force
    @out = out
  end

  def call
    @stamp = Time.current.strftime("%Y%m%d%H%M%S")
    @work_dir = Rails.root.join("tmp/go_import", "#{@stamp}-#{SecureRandom.hex(4)}").tap(&:mkpath)
    stage
    build
    @report.lines.each { @out.puts it }

    return finish("Nothing was changed.") if @dry_run
    if @report.target_users.positive? && !@force
      raise Error, "This install already has users: importing replaces its whole site. Re-run with FORCE=1 to replace it (the current database is kept beside it)."
    end

    apply
    finish("Done. Everyone is signed out: sign in with an account from the imported site.")
  rescue Archive::Unsafe => e
    raise Error, "#{@source} can't be imported: #{e.message}"
  ensure
    FileUtils.rm_rf(@work_dir) if @work_dir
  end

  private

  # ── 1. Unpacked and checked ───────────────────────────────────────────

  def stage
    raise Error, "No such file or directory: #{@source}" unless @source.exist?
    raise Error, "#{@source} is this install's own database" if @source.directory? && same_file?(@source.join("cms.sqlite3"), target_db)

    @archive = Archive.new(@source, into: @work_dir.join("staged")).unpack
    @report = Report.new(source: @source.to_s, manifest: @archive.manifest)
    @report.dry_run = @dry_run
    if @archive.manifest && @archive.manifest["format"].present? && @archive.manifest["format"] != Archive::FORMAT
      @report.warn("manifest.json says it's #{@archive.manifest["format"].inspect}; importing it as a Go core backup")
    end
    @report.warn("#{@archive.ignored.size} entries in it aren't part of a site and were left out (#{@archive.ignored.first(5).join(", ")})") if @archive.ignored.any?
    @keyring = Keyring.new(*[@archive.key, *@secret_keys].compact_blank)
    check_database
  end

  def check_database
    db = SQLite3::Database.new(@archive.database.to_s)
    result = db.get_first_value("PRAGMA quick_check")
    raise Error, "The backup's database is damaged (#{result})" unless result == "ok"

    tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
    missing = %w[users roles pages settings] - tables
    raise Error, "The backup's database isn't a Libre Publish site's (it has no #{missing.join(", ")} table)" if missing.any?

    version = db.get_first_value("PRAGMA user_version").to_i
    @report.warn("it was written by a newer Go core (schema #{version}) than this import was made for (#{SCHEMA_VERSION}): what that version added is left out") if version > SCHEMA_VERSION
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
  rescue SQLite3::Exception => e
    raise Error, "The backup's database can't be read (#{e.message})"
  ensure
    db&.close
  end

  # ── 2. The new database ───────────────────────────────────────────────

  def built_db = @work_dir.join("main.sqlite3")

  def build
    db = SQLite3::Database.new(built_db.to_s)
    db.execute("ATTACH DATABASE ? AS go", [@archive.database.to_s])
    tables = Tables.new(db, target: ActiveRecord::Base.connection, report: @report)
    tables.create_schema
    tables.copy
    mine = tables.tables("main")
    Content.new(db, report: @report, tables: mine).convert
    @plugin_data = Forms.new(db, report: @report, tables: mine).convert
    Secrets.new(db, keyring: @keyring, report: @report).carry
    check_key
    files(db)
    report_webhooks(db)
    report_left_behind(db)
    @report.owners = db.execute("SELECT u.email FROM users u JOIN roles r ON r.id = u.role_id WHERE r.system = 1 ORDER BY u.id").flatten
    @report.warn("no one in it has the system Admin role: make someone an admin with bin/rails cms:reset_admin_password after") if @report.owners.empty?
    db.execute("DETACH DATABASE go")
    @report.target_users = target_users
  ensure
    db&.close
  end

  # A key given that opens none of the secrets is a typo, or another
  # install's: refused before anything changes.
  def check_key
    secrets = @report.secrets
    if @secret_keys.any? && secrets[:total].positive? && secrets[:carried].zero?
      raise Error, "That key doesn't open the backup's sealed values (#{secrets[:total]} of them): it's another install's, or mistyped"
    end
    if secrets[:cleared].any? && @keyring.empty?
      @report.warn("the backup's secrets were sealed with the Go install's key, and none was given: give its secret.key with SECRET_KEY_FILE (or its SECRET_KEY as GO_SECRET_KEY) to carry them")
    end
  end

  # Each blob's file, checked against its size and checksum; the blobs
  # pointed at this install's storage service.
  def files(db)
    service = ActiveStorage::Blob.service
    if !service.respond_to?(:path_for)
      raise Error, "This install's Active Storage service (#{service.class}) isn't the Disk service; move the files by hand." unless @dry_run

      @report.warn("this install's Active Storage service isn't the Disk service: the files would have to be moved by hand")
    end
    db.execute("UPDATE active_storage_blobs SET service_name = ?", [service.name.to_s])
    @blobs = db.execute("SELECT id, key, filename, byte_size, checksum FROM active_storage_blobs ORDER BY id").map do |id, key, filename, size, checksum|
      file = @archive.blobs[key]
      state =
        if file.nil? then :missing
        elsif file[:size] != size.to_i || (checksum.present? && file[:md5] != checksum) then :damaged
        else :whole
        end
      @report.files[state] += 1
      @report.warn("file #{filename} (blob ##{id}): #{state}") unless state == :whole
      {key:, state:}
    end
    stray = @archive.blobs.size - @blobs.count { it[:state] != :missing }
    @report.files[:not_named_by_any_blob] += stray if stray.positive?
  end

  def report_webhooks(db)
    db.execute("SELECT name, kind, testing_url FROM go.webhooks").each do |name, kind, testing_url|
      @report.not_carry("webhook #{name}: its body map (an external webhook's shape; this core sends its own envelope)") if kind.present? && kind != "internal"
      @report.not_carry("webhook #{name}: its testing address (#{testing_url})") if testing_url.present?
    end
  rescue SQLite3::SQLException
    nil
  end

  def report_left_behind(db)
    open = db.get_first_value("SELECT COUNT(*) FROM go.revisions WHERE status = 'open'").to_i
    @report.not_carry("#{open} change(s) waiting for review on the Go core: review them there first, or make them again") if open.positive?
  rescue SQLite3::SQLException
    nil
  end

  def target_users
    ActiveRecord::Base.connection.table_exists?("users") ? User.count : 0
  end

  # ── 4. Applied ────────────────────────────────────────────────────────

  def target_db
    Pathname(ActiveRecord::Base.connection_db_config.database).expand_path(Rails.root)
  end

  def apply
    @report.kept = replace_database
    copy_files
    write_plugin_data
    SearchIndexed.reindex_all
    Event.record("site_backup.imported", format: "librepublish-go", source: @source.basename.to_s, files: @report.files.to_h,
      secrets: @report.secrets.slice(:total, :carried), forms: @report.forms.to_h)
  end

  def replace_database
    ActiveRecord::Base.connection_pool.disconnect!
    kept = Pathname("#{target_db}.before-import-#{@stamp}")
    FileUtils.mv(target_db, kept) if target_db.file?
    %w[-wal -shm].each { FileUtils.mv("#{target_db}#{it}", "#{kept}#{it}") if File.exist?("#{target_db}#{it}") }
    FileUtils.mkdir_p(target_db.dirname)
    FileUtils.cp(built_db, target_db)
    ActiveRecord::Base.descendants.reject(&:abstract_class?).each(&:reset_column_information)
    kept if kept.file?
  end

  def copy_files
    service = ActiveStorage::Blob.service
    @blobs.each do |blob|
      next if blob[:state] == :missing

      destination = Pathname(service.path_for(blob[:key]))
      FileUtils.mkdir_p(destination.dirname)
      FileUtils.cp(@archive.blob_path(blob[:key]), destination)
    end
  end

  def write_plugin_data
    return if @plugin_data.blank?

    path = target_db.dirname.join("go-plugins-#{@stamp}.json")
    path.write(JSON.pretty_generate(@plugin_data))
    File.chmod(0o600, path)
    @report.plugin_data = path
  end

  def finish(message)
    @out.puts "  the previous database is at #{@report.kept}" if @report.kept
    @out.puts "  the Go plugins' records are in #{@report.plugin_data}" if @report.plugin_data
    @out.puts message
    self
  end

  def same_file?(a, b) = File.exist?(a) && File.exist?(b) && File.identical?(a, b)
end
