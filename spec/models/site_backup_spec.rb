# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"
require "zlib"
require "tmpdir"

RSpec.describe SiteBackup do
  # `dump_to` leaves the IO open; read the captured bytes back through a
  # fresh reader.
  def entries_of(backup)
    io = StringIO.new(+"", "w+b")
    backup.dump_to(io)
    read_entries(io.string)
  end

  def read_entries(bytes)
    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(bytes)) do |gz|
      Gem::Package::TarReader.new(gz) do |tar|
        tar.each { |entry| entries[entry.full_name] = entry.read }
      end
    end
    entries
  end

  it "produces a tar.gz with the manifest and the database" do
    entries = entries_of(described_class.new)

    expect(entries.keys).to include("manifest.json", "db/main.sqlite3")
    expect(JSON.parse(entries["manifest.json"])["tenant"]).to eq(Site.key)
  end

  context "with committed writes" do
    self.use_transactional_tests = false

    after { Page.where(slug: "fresh").delete_all }

    it "snapshots the committed database, writes not yet checkpointed out of the WAL included" do
      Page.create!(slug: "fresh", title: "Fresh", status: "draft", locale: "en")

      entries = entries_of(described_class.new)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "main.sqlite3")
        File.binwrite(path, entries["db/main.sqlite3"])
        db = SQLite3::Database.new(path, readonly: true)
        expect(db.get_first_value("SELECT title FROM pages WHERE slug = 'fresh'")).to eq("Fresh")
      ensure
        db&.close
      end
    end
  end

  it "fails rather than shipping a bundle when the database can't be copied" do
    allow_any_instance_of(SQLite3::Backup).to receive(:step).and_return(SQLite3::Constants::ErrorCode::BUSY)

    expect { entries_of(described_class.new) }.to raise_error(SiteBackup::SnapshotFailed)
  end

  it "names attached blobs whose file is missing instead of skipping them silently" do
    page = Page.create!(slug: "with-file", title: "With file", status: "draft", locale: "en")
    kept = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("kept"), filename: "kept.txt")
    gone = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("gone"), filename: "gone.txt")
    ActiveStorage::Attachment.create!(name: "file", record: page, blob: kept)
    # Attaching touches the page, which bumps its lock_version.
    ActiveStorage::Attachment.create!(name: "other", record: page.reload, blob: gone)
    missing_key = gone.key
    File.delete(ActiveStorage::Blob.service.path_for(missing_key))

    entries = entries_of(described_class.new)
    manifest = JSON.parse(entries["manifest.json"])

    expect(manifest["missing_blobs"]).to eq([missing_key])
    expect(manifest["includes"]["blobs"]).to eq(1)
    expect(entries["blobs/#{kept.key}"]).to eq("kept")
    expect(entries.keys).not_to include("blobs/#{missing_key}")
  end

  it "exports to a temporary file read back in chunks, gone once the response is sent" do
    download = described_class.new.export
    path = download.instance_variable_get(:@file).path

    body = +""
    download.each { body << it }
    expect(body.bytesize).to eq(download.bytesize)
    expect(read_entries(body).keys).to include("manifest.json", "db/main.sqlite3")
    expect(AuditLog.last.action).to eq("site_backup.exported")

    download.close
    expect(File.exist?(path)).to be(false)
  end

  it "uses an informative filename" do
    expect(described_class.new.filename).to match(/\Acms-backup-#{Regexp.escape(Site.key)}-\d{8}-\d{6}\.tar\.gz\z/)
  end
end
