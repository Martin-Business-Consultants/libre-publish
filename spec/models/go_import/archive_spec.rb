# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoImport::Archive do
  let(:dir) { Pathname(Dir.mktmpdir("go-archive")) }
  let(:staging) { dir.join("staging") }
  let(:key) { "abcd1234efgh5678" }

  after { FileUtils.rm_rf(dir) }

  # entries: name => body, or name => [typeflag, body] for a link or a device.
  def archive(entries, gzip: true, name: "backup.tar.gz")
    dir.join(name).tap do |path|
      File.open(path, "wb") do |file|
        io = gzip ? Zlib::GzipWriter.new(file) : file
        Gem::Package::TarWriter.new(io) do |tar|
          entries.each do |entry, body|
            if body.is_a?(Array)
              tar.add_symlink(entry, body.last, 0o777)
            else
              tar.add_file_simple(entry, 0o644, body.bytesize) { it.write(body) }
            end
          end
        end
        io.close if gzip
      end
    end
  end

  def unpack(source, **options) = described_class.new(source, into: staging, **options).unpack

  it "writes only what a backup holds, each where it's built to go, with each file's checksum" do
    unpacked = unpack(archive({"manifest.json" => {format: "librepublish-go"}.to_json, "cms.sqlite3" => "db", "secret.key" => "ab\n",
      "storage/ab/cd/#{key}" => "file", "storage/xx/yy/#{key}" => "misfiled", "notes.txt" => "?", "./cms.sqlite3-wal" => "wal"}))

    expect(unpacked.manifest).to eq("format" => "librepublish-go")
    expect(unpacked.key).to eq("ab")
    expect(unpacked.database.read).to eq("db")
    expect(staging.join("cms.sqlite3-wal").read).to eq("wal")
    expect(unpacked.blobs).to eq(key => {size: 4, md5: Digest::MD5.base64digest("file")})
    expect(unpacked.blob_path(key).read).to eq("file")
    expect(unpacked.ignored).to contain_exactly("storage/xx/yy/#{key}", "notes.txt")
  end

  it "reads a plain tar as well" do
    expect(unpack(archive({"cms.sqlite3" => "db"}, gzip: false, name: "backup.tar")).database.read).to eq("db")
  end

  it "refuses an entry that's absolute, climbs out, or is a link" do
    expect { unpack(archive({"/etc/cms.sqlite3" => "x"})) }.to raise_error(described_class::Unsafe, /absolute path/)
    expect { unpack(archive({"storage/../../cms.sqlite3" => "x"})) }.to raise_error(described_class::Unsafe, /climbs out/)
    expect { unpack(archive({"a\\b" => "x"})) }.to raise_error(described_class::Unsafe, /backslash/)
    expect { unpack(archive({"cms.sqlite3" => [:link, "/etc/passwd"]})) }.to raise_error(described_class::Unsafe, /link or a device/)
    expect(dir.glob("**/passwd")).to be_empty
  end

  it "refuses an archive past its limits, counting what it skips too" do
    small = GoImport::Archive::Limits.new(total: 10, file: 5, entries: 3)

    expect { unpack(archive({"cms.sqlite3" => "123456"}), limits: small) }.to raise_error(described_class::Unsafe, /over the limit of 5/)
    expect { unpack(archive({"a" => "12345", "b" => "123456", "cms.sqlite3" => "1"}), limits: small) }.to raise_error(described_class::Unsafe, /over 10 bytes/)
    expect { unpack(archive({"a" => "", "b" => "", "c" => "", "cms.sqlite3" => ""}), limits: small) }.to raise_error(described_class::Unsafe, /more than 3 entries/)
  end

  it "refuses what has no database, and what isn't an archive" do
    expect { unpack(archive({"manifest.json" => "{}"})) }.to raise_error(described_class::Unsafe, /no cms.sqlite3/)
    expect { unpack(dir.join("junk.tar.gz").tap { it.write("\x1f\x8bnot gzip") }) }.to raise_error(described_class::Unsafe, /isn't a backup archive/)
  end

  it "copies a directory (a data directory), leaving out what an install keeps beside its data, and refuses a link in it" do
    source = dir.join("data").tap(&:mkpath)
    source.join("cms.sqlite3").write("db")
    source.join("storage/ab/cd").tap(&:mkpath).join(key).write("file")
    source.join("backups").tap(&:mkpath).join("cms.sqlite3").write("old")

    expect(unpack(source)).to have_attributes(blobs: {key => {size: 4, md5: Digest::MD5.base64digest("file")}})
    expect(staging.join("cms.sqlite3").read).to eq("db")

    File.symlink("/etc/passwd", source.join("storage/ab/cd/linked"))
    expect { described_class.new(source, into: dir.join("again")).unpack }.to raise_error(described_class::Unsafe, /link or a device/)
  end

  it "tells the Go core's backup from the Rails core's" do
    expect(described_class.go?(archive({"manifest.json" => {format: "librepublish-go"}.to_json}, name: "go.tar.gz"))).to be(true)
    expect(described_class.go?(archive({"cms.sqlite3" => "db"}, name: "bare.tar.gz"))).to be(true)
    expect(described_class.go?(archive({"manifest.json" => {tenant: "acme"}.to_json, "db/main.sqlite3" => "db"}, name: "rails.tar.gz"))).to be(false)
    expect(described_class.go?(dir.join("rails").tap(&:mkpath).tap { it.join("main.sqlite3").write("db") })).to be(false)
    expect(described_class.go?(dir.join("go").tap(&:mkpath).tap { it.join("cms.sqlite3").write("db") })).to be(true)
    expect(described_class.go?(dir.join("nowhere"))).to be(false)
    expect(described_class.go?(dir.join("junk").tap { it.write("junk") })).to be(false)
  end
end
