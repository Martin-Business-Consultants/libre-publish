# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "rubygems/package"
require "zlib"

# A Go core backup (Tools › Backup there, GET /api/tools/backup), unpacked
# into a staging directory: a .tar.gz or a plain .tar of
#
#   manifest.json                  {"format": "librepublish-go", "schema_version": …}
#   cms.sqlite3 (and -wal)         the site's database
#   storage/<k0k1>/<k2k3>/<key>    each uploaded file, by its blob key
#   secret.key                     the install's key, when the backup was asked to include it
#
# or a directory holding them (an unpacked backup, or the Go install's data
# directory itself). As the Go core's own import does (internal/restore/
# extract.go), only those entries are written, each to a path built here
# rather than taken from the archive; an entry that's absolute, climbs out
# with "..", or is a link or a device refuses the whole archive, as does one
# past the size limits (a gzip bomb stops there).
class GoImport::Archive
  class Unsafe < StandardError; end

  Limits = Data.define(:total, :file, :entries)
  DEFAULT_LIMITS = Limits.new(total: 64 * 1024**3, file: 32 * 1024**3, entries: 2_000_000)

  FORMAT = "librepublish-go"
  DATABASE = "cms.sqlite3"
  BLOB_KEY = /\A[a-z0-9]{4,128}\z/
  # What an install keeps beside its data, not worth descending into.
  SKIPPED_DIRECTORIES = %w[imports backups variants releases site_imports].freeze

  attr_reader :manifest, :key, :blobs, :ignored, :database

  # Whether path is a Go core backup (or data directory) rather than a Rails
  # one: its manifest says so, or it holds cms.sqlite3. Reads an archive only
  # as far as its first entries.
  def self.go?(path)
    path = Pathname(path.to_s)
    if path.directory?
      path.join(DATABASE).file? || manifest_format(path.join("manifest.json").read) == FORMAT
    elsif path.file?
      each_header(path) do |name, entry|
        return manifest_format(entry.read(1.megabyte).to_s) == FORMAT if name == "manifest.json"
        return true if name == DATABASE
        return false if name.end_with?(".sqlite3")
      end
      false
    else
      false
    end
  rescue Zlib::Error, Gem::Package::Error, Errno::ENOENT, Errno::EISDIR
    false
  end

  def self.manifest_format(text)
    JSON.parse(text)["format"] if text.present?
  rescue JSON::ParserError
    nil
  end

  def self.each_header(path)
    File.open(path, "rb") do |file|
      io = file.read(2) == "\x1f\x8b".b ? (file.rewind && Zlib::GzipReader.new(file)) : file.tap(&:rewind)
      Gem::Package::TarReader.new(io) do |tar|
        tar.each { yield it.full_name.delete_prefix("./"), it }
      end
    end
  end

  def initialize(source, into:, limits: DEFAULT_LIMITS)
    @source = Pathname(source.to_s).expand_path
    @root = Pathname(into.to_s).tap(&:mkpath)
    @limits = limits
    @total = 0
    @entries = 0
    @blobs = {}
    @ignored = []
  end

  def unpack
    @source.directory? ? from_directory : from_archive
    raise Unsafe, "#{@source} has no #{DATABASE}: it isn't a Go core backup" unless @database
    self
  end

  def storage = @root.join("storage")

  def blob_path(key) = storage.join(key[0, 2], key[2, 2], key)

  private

  def from_archive
    self.class.each_header(@source) do |_, item|
      name = clean(item.full_name)
      case item.header.typeflag
      when "0", "\0", "", "7"
        entry(name, item.header.size, item) if name
      when "5", "g", "x"
        next
      else
        raise Unsafe, "the entry #{item.full_name.inspect} is a link or a device, which a backup never holds"
      end
    end
  rescue Zlib::Error, Gem::Package::Error => e
    raise Unsafe, "#{@source} isn't a backup archive (#{e.message})"
  end

  def from_directory
    Find.find(@source.to_s) do |path|
      next if path == @source.to_s

      name = clean(Pathname(path).relative_path_from(@source).to_s)
      stat = File.lstat(path)
      if stat.directory?
        Find.prune if SKIPPED_DIRECTORIES.include?(name) || name.start_with?("replaced-")
      elsif stat.file?
        File.open(path, "rb") { entry(name, stat.size, it) }
      else
        raise Unsafe, "#{name} is a link or a device; copy the files themselves"
      end
    end
  end

  # An entry's name as a relative path, or nil for the archive's root.
  def clean(name)
    raise Unsafe, "the entry #{name.inspect} has a backslash or NUL in its name" if name.match?(/[\\\0]/)
    raise Unsafe, "the entry #{name.inspect} is an absolute path" if name.start_with?("/")
    raise Unsafe, "the entry #{name.inspect} climbs out of the archive" if name.split("/").include?("..")

    parts = name.split("/").reject { it.empty? || it == "." }
    raise Unsafe, "the entry #{name.inspect} isn't a local path" if parts.first&.match?(/\A[a-zA-Z]:\z/)

    parts.join("/").presence
  end

  def entry(name, size, io)
    @entries += 1
    raise Unsafe, "the backup is too large: more than #{@limits.entries} entries" if @entries > @limits.entries

    # Everything counts, kept or skipped: a bomb is caught however it's packed.
    @total += size
    raise Unsafe, "the backup is too large: it unpacks to over #{@limits.total} bytes" if @total > @limits.total

    kind, ref = classify(name)
    if kind == :ignored
      @ignored << name if @ignored.size < 1000
      return
    end
    raise Unsafe, "the backup is too large: #{name} is #{size} bytes, over the limit of #{@limits.file}" if size > @limits.file

    case kind
    when :manifest, :key
      raise Unsafe, "#{name} is too large to be one" if size > 1.megabyte

      text = io.read(size).to_s
      if kind == :key
        @key = text.strip
      else
        @manifest = JSON.parse(text)
      end
    when :database
      @database = @root.join(DATABASE).tap { write(it, size, io) }
    when :wal
      write(@root.join("#{DATABASE}-wal"), size, io)
    when :blob
      @blobs[ref] = {size:, md5: write(blob_path(ref), size, io)}
    end
  rescue JSON::ParserError => e
    raise Unsafe, "manifest.json isn't JSON (#{e.message})"
  end

  def classify(name)
    return [:database, nil] if name == DATABASE
    return [:wal, nil] if name == "#{DATABASE}-wal"
    return [:manifest, nil] if name == "manifest.json"
    return [:key, nil] if name == "secret.key"

    parts = name.split("/")
    parts.shift if parts.first == "storage"
    key = parts[2]
    if parts.size == 3 && key.match?(BLOB_KEY) && parts[0] == key[0, 2] && parts[1] == key[2, 2]
      [:blob, key]
    else
      [:ignored, nil]
    end
  end

  # Exactly size bytes of io to path, and their MD5 (Active Storage's
  # checksum, base64).
  def write(path, size, io)
    FileUtils.mkdir_p(path.dirname)
    md5 = Digest::MD5.new
    written = 0
    File.open(path, "wb") do |file|
      while written < size && (chunk = io.read([64.kilobytes, size - written].min))
        file.write(chunk)
        md5 << chunk
        written += chunk.bytesize
      end
    end
    raise Unsafe, "#{path.basename} is cut short (#{written} of #{size} bytes)" if written != size

    md5.base64digest
  end
end
