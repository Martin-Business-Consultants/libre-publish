# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require "json"
require "tempfile"

# Bundles the site's data into a tar.gz the editor can download.
# The bundle contains:
#
#   manifest.json    — site key, generated_at, file inventory, and the keys
#                      of any attached blob whose file is missing
#   db/main.sqlite3  — the primary database, as a consistent snapshot
#   blobs/<key>      — every Active Storage blob attached to a record in this
#                      DB (the media library's files, a form's uploads…)
#
# Only the primary database is included: the cache, queue and cable
# databases hold nothing a restore needs (Solid Cache, Solid Queue's jobs,
# Action Cable's messages) and rebuild themselves empty.
#
# Restoration is left as a manual / ops process for now. The intent is "I
# can leave this provider and take my data with me," not "one-click
# import into a fresh instance."
class SiteBackup
  # Raised rather than silently shipping a bundle with no database in it.
  # An empty backup that reports success is worse than a failed one.
  MissingDatabase = Class.new(StandardError)
  # Raised when SQLite's backup of the live database doesn't complete.
  SnapshotFailed = Class.new(StandardError)
  # How long the copy waits on a lock before giving up.
  BUSY_TIMEOUT_MS = 10_000

  # What a backup would hold, by kind: the core's content and what enabled
  # plugins count (`counts … backup: true`), in reading order.
  def self.contents
    core = {
      pages:       Page.count,
      collections: Collection.count,
      entries:     CollectionEntry.count,
      block_types: BlockType.count,
      globals:     Global.count
    }
    additions = Cms::Plugins.enabled_counters.select(&:backup).map { |counter| [counter.name, counter.count.call, counter.after] }
    Cms::Plugins.arrange(core.to_a, additions).to_h
  end

  # The archives bin/update and the container's boot left in the data
  # directory (Cms::DataBackup), newest first.
  def self.data_archives
    Cms::DataBackup.for_install.archives
  end

  # The whole bundle, built into a temporary file and handed out as a
  # response body that reads it back in chunks (Download), recorded as an
  # export. Nothing the size of the site is ever held in memory.
  def export
    file = Tempfile.create(["cms-backup", ".tar.gz"], binmode: true)
    bytes = dump_to(file)
    Event.record("site_backup.exported", bytes: bytes)
    file.rewind
    Download.new(file)
  rescue StandardError
    file&.close
    File.delete(file.path) if file && File.exist?(file.path)
    raise
  end

  # Streams the tar.gz bundle into the given IO, leaving it open. Returns the
  # byte count written so the controller can log it.
  def dump_to(io)
    counter = ByteCounter.new(io)

    snapshot_database do |db_file|
      Zlib::GzipWriter.wrap(counter) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          write_manifest(tar)
          add_file(tar, "db/main.sqlite3", db_file)
          write_blobs(tar)
        end
      end
    end

    counter.bytes
  end

  def filename
    "cms-backup-#{Site.key}-#{Time.current.strftime("%Y%m%d-%H%M%S")}.tar.gz"
  end

  private

  def write_manifest(tar)
    payload = {
      tenant:        Site.key,
      generated_at:  Time.current.iso8601,
      includes:      {db: true, blobs: blob_keys.size - missing_blob_keys.size},
      missing_blobs: missing_blob_keys
    }
    body = JSON.pretty_generate(payload)
    tar.add_file_simple("manifest.json", 0o644, body.bytesize) { |io| io.write(body) }
  end

  # A consistent copy of the primary database's committed data, taken with
  # SQLite's online backup API over a read-only connection of its own (as
  # Cms::DataBackup does): writes still in the WAL are included, and a write
  # landing mid-copy can't tear it. Any failure raises — a backup without its
  # database is not a backup.
  def snapshot_database
    path = db_path
    raise MissingDatabase, "no database file at #{path.inspect}" unless path.present? && File.exist?(path)

    Tempfile.create(["cms-backup-db", ".sqlite3"], binmode: true) do |file|
      copy_database(path, file.path)
      File.open(file.path, "rb") { yield it }
    end
  end

  def copy_database(source, destination)
    from = SQLite3::Database.new(source, readonly: true)
    from.busy_timeout = BUSY_TIMEOUT_MS
    to = SQLite3::Database.new(destination)
    backup = SQLite3::Backup.new(to, "main", from, "main")
    result = backup.step(-1)
    backup.finish
    raise SnapshotFailed, "the database backup stopped (SQLite result #{result})" unless result == SQLite3::Constants::ErrorCode::DONE
  ensure
    to&.close
    from&.close
  end

  def write_blobs(tar)
    blob_keys.each do |key|
      next if missing_blob_keys.include?(key)

      File.open(blob_path_for(key), "rb") { add_file(tar, "blobs/#{key}", it) }
    end
  end

  # Attached blobs with no file on disk. Named in the manifest rather than
  # skipped without a word, so a restore knows what it lacks.
  def missing_blob_keys
    @missing_blob_keys ||= blob_keys.reject do |key|
      path = blob_path_for(key)
      path && File.exist?(path)
    end
  end

  def blob_keys
    @blob_keys ||= ActiveStorage::Attachment
      .joins(:blob)
      .pluck("active_storage_blobs.key")
      .uniq
  end

  def db_path
    @db_path ||= ApplicationRecord.connection_db_config.database.to_s
  end

  # Where the Disk service keeps a blob. Asked of the service rather than
  # rebuilt here: rebuilding it by hand is how blobs used to go missing from
  # backups without an error.
  def blob_path_for(key)
    service = ActiveStorage::Blob.service
    service.path_for(key) if service.respond_to?(:path_for)
  end

  # Copies a file into the archive in chunks, never whole.
  def add_file(tar, name, file)
    tar.add_file_simple(name, 0o644, file.size) { |io| IO.copy_stream(file, io) }
  end
end
