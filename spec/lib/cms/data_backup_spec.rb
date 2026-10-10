# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cms::DataBackup do
  let(:data_dir) { Pathname(Dir.mktmpdir("cms-data")) }

  after { data_dir.rmtree }

  def archive_entries(archive) = IO.popen(["tar", "-tzf", archive], &:read).lines.map(&:strip)

  it "copies every database and file into one archive, and skips its own backups" do
    db = SQLite3::Database.new(data_dir.join("production.sqlite3").to_s)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("CREATE TABLE t (v TEXT)")
    db.execute("INSERT INTO t VALUES ('kept')")
    data_dir.join("ab/cd").mkpath
    data_dir.join("ab/cd/blob").write("uploaded")
    data_dir.join("plugins/seo").mkpath
    data_dir.join("plugins/seo/seo.gemspec").write("")
    data_dir.join("releases/v9.9.9").mkpath
    data_dir.join("releases/v9.9.9/VERSION").write("9.9.9")
    data_dir.join("site_imports/1").mkpath
    data_dir.join("site_imports/1/archive.tar.gz").write("big")

    archive = described_class.new(data_dir: data_dir).call

    expect(archive).to start_with(data_dir.join("backups").to_s)
    entries = archive_entries(archive)
    expect(entries).to include("./production.sqlite3", "./ab/cd/blob", "./plugins/seo/seo.gemspec")
    expect(entries.grep(/backups|-wal|-shm|releases|site_imports/)).to be_empty

    Dir.mktmpdir do |out|
      system("tar", "-xzf", archive, "-C", out, exception: true)
      copy = SQLite3::Database.new(File.join(out, "production.sqlite3"))
      expect(copy.execute("SELECT v FROM t")).to eq([["kept"]])
      copy.close
    end
  ensure
    db&.close
  end

  it "keeps the newest few" do
    SQLite3::Database.new(data_dir.join("production.sqlite3").to_s).close
    backups = data_dir.join("backups").tap(&:mkpath)
    %w[20200101-000000 20200102-000000 20200103-000000].each { backups.join("cms-data-#{it}.tar.gz").write("") }

    described_class.new(data_dir: data_dir, keep: 2).call

    expect(backups.children.map { it.basename.to_s }.sort.first).not_to include("20200101")
    expect(backups.children.size).to eq(2)
  end

  it "has nothing to do for a fresh install" do
    expect(described_class.new(data_dir: data_dir).call).to be_nil
  end

  it "refuses to archive a database it couldn't copy whole" do
    SQLite3::Database.new(data_dir.join("production.sqlite3").to_s).close
    allow_any_instance_of(SQLite3::Backup).to receive(:step).and_return(SQLite3::Constants::ErrorCode::BUSY)

    expect { described_class.new(data_dir: data_dir).call }.to raise_error(Cms::DataBackup::CopyFailed, /production.sqlite3/)
    expect(Dir.glob(data_dir.join("backups/*.tar.gz").to_s)).to be_empty
  end

  describe "nightly, copied off the server" do
    before { SQLite3::Database.new(data_dir.join("production.sqlite3").to_s).close }

    it "hands the archive to CMS_BACKUP_COMMAND as its last argument" do
      shipped = data_dir.join("shipped.txt")
      archive = described_class.new(data_dir: data_dir, command: "sh -c 'echo \"$0\" > #{shipped}'").nightly

      expect(shipped.read.strip).to eq(archive)
    end

    it "fails when the command does" do
      expect { described_class.new(data_dir: data_dir, command: "false").nightly }.to raise_error(RuntimeError)
    end

    it "only archives without a command" do
      backup = described_class.new(data_dir: data_dir)

      expect(backup.nightly).to end_with(".tar.gz")
      expect(backup.ship("anything")).to be(false)
    end

    it "reads the command from the environment" do
      expect(described_class.for_install("CMS_DATA_DIR" => data_dir.to_s, "CMS_BACKUP_COMMAND" => "rclone copy").command).to eq("rclone copy")
      expect(described_class.for_install("CMS_DATA_DIR" => data_dir.to_s, "CMS_BACKUP_COMMAND" => " ").command).to be_nil
    end
  end

  describe "on boot, only when migrations are pending" do
    let(:migrations) { Pathname(Dir.mktmpdir("migrations")).tap { it.join("20260101000000_one.rb").write(""); it.join("20260202000000_two.rb").write("") } }

    after { migrations.rmtree }

    def primary(applied)
      db = SQLite3::Database.new(data_dir.join("production.sqlite3").to_s)
      db.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY)")
      applied.each { db.execute("INSERT INTO schema_migrations VALUES (?)", [it]) }
      db.close
    end

    it "backs up when the database lacks a migration the code has" do
      primary(%w[20260101000000])
      backup = described_class.new(data_dir: data_dir)

      expect(backup.pending_migrations?(migrations_dirs: [migrations])).to be(true)
      expect(backup.call_if_pending(migrations_dirs: [migrations])).to end_with(".tar.gz")
    end

    it "takes none on a plain restart, with every migration applied" do
      primary(%w[20260101000000 20260202000000])
      backup = described_class.new(data_dir: data_dir)

      expect(backup.call_if_pending(migrations_dirs: [migrations])).to be_nil
      expect(data_dir.join("backups")).not_to exist
    end

    it "takes none on a fresh install, which has no database yet" do
      expect(described_class.new(data_dir: data_dir).call_if_pending(migrations_dirs: [migrations])).to be_nil
    end

    it "finds the app's and the engines' migrations" do
      dirs = described_class.migrations_dirs(Rails.root.to_s)

      expect(dirs).to include(Rails.root.join("db/migrate").to_s, Rails.root.join("engines/hello/db/migrate").to_s)
    end
  end
end
