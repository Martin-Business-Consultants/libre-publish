# frozen_string_literal: true

require "rails_helper"

# Installs from a real tarball laid out as GitHub serves one (a top directory
# named for the repository and commit), into a data directory of its own.
# GitHub and the restart are stood in for.
RSpec.describe PluginChange do
  include ActiveJob::TestHelper

  let(:data_dir) { Pathname(Dir.mktmpdir("plugin-change")) }
  let(:admin) { create(:user) }
  let(:github) { instance_double(UpdateCheck::Github) }

  around { |example| with_env("CMS_DATA_DIR" => data_dir.to_s) { example.run } }

  before do
    allow(UpdateCheck::Github).to receive(:new).with(repo: "acme/cms-thing").and_return(github)
    allow(github).to receive(:get).with("releases/latest").and_return("tag_name" => "v1.2.0")
    allow(Cms::Restart).to receive(:later)
    InstalledPlugins.loaded.clear
    InstalledPlugins.failed.clear
    InstalledPlugins.versions.clear
    InstalledPlugins.origins.clear
  end

  after do
    FileUtils.rm_rf(data_dir)
    InstalledPlugins.loaded.clear
    InstalledPlugins.failed.clear
    InstalledPlugins.versions.clear
    InstalledPlugins.origins.clear
  end

  def release(files)
    dir = Pathname(Dir.mktmpdir("release"))
    top = dir.join("acme-cms-thing-abc1234").tap(&:mkpath)
    files.each { |name, body| top.join(name).tap { it.dirname.mkpath }.write(body) }
    archive = dir.join("release.tar.gz")
    system("tar", "-czf", archive.to_s, "-C", dir.to_s, top.basename.to_s, exception: true)
    @archive = archive
    allow(github).to receive(:download) do |url, path|
      expect(url).to eq("https://api.github.com/repos/acme/cms-thing/tarball/v1.2.0")
      FileUtils.cp(archive, path)
      path
    end
  end

  def plugin_release(name = "thing") = release("#{name}.gemspec" => "", "lib/#{name}.rb" => "module Thing; end")

  def installed = InstalledPlugins.directory.join("thing")

  describe ".install" do
    it "takes a repository as owner/name, or as its GitHub address" do
      change = described_class.install("https://github.com/acme/cms-thing.git", by: admin)

      expect(change).to have_attributes(repo: "acme/cms-thing", action: "install", status: "running", requested_by: admin)
      expect(PluginChangeJob).to have_been_enqueued.with(change)
    end

    it "puts the latest release in the data directory, says where it came from, and restarts" do
      plugin_release

      change = described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs

      expect(change.reload).to have_attributes(key: "thing", to_version: "1.2.0", status: "running")
      expect(installed.join("lib/thing.rb")).to exist
      expect(InstalledPlugins.metadata("thing")).to include("repo" => "acme/cms-thing", "version" => "1.2.0", "tag" => "v1.2.0")
      expect(InstalledPlugins.directory.children.map { it.basename.to_s }).to eq(["thing"])
      expect(Cms::Restart).to have_received(:later).with(report: change.report)
    end

    it "fails a release that isn't a plugin, and leaves nothing behind" do
      release("README.md" => "hello")

      change = described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs

      expect(change.reload).to have_attributes(status: "failed", message: a_string_matching(/isn't a CMS plugin/))
      expect(InstalledPlugins.directory.children).to be_empty
      expect(Cms::Restart).not_to have_received(:later)
    end

    it "won't install a plugin twice, or one the install already bundles" do
      plugin_release
      described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs
      described_class.running.update_all(status: "succeeded")

      again = described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs
      expect(again.reload.message).to match(/already installed/)

      FileUtils.rm_rf(installed)
      InstalledPlugins.loaded["hello"] = Rails.root.join("engines/hello")
      plugin_release("hello")
      bundled = described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs
      expect(bundled.reload.message).to match(/already installed/)
    end

    it "is one change at a time, and wants a repository" do
      described_class.install("acme/cms-thing", by: admin)

      expect { described_class.install("acme/other", by: admin) }.to raise_error(described_class::Refused, /under way/)
      described_class.running.update_all(status: "succeeded")
      expect { described_class.install("not a repo", by: admin) }.to raise_error(ActiveRecord::RecordInvalid, /owner\/name/)
    end
  end

  describe "from the plugin directory" do
    let(:listed) do
      PluginDirectory::Entry.new(key: "thing", kind: "plugin", name: "Thing", description: "x", repo: "acme/cms-thing", author: nil,
        homepage: nil, version: "1.3.0", commit: "c" * 40, requires: nil)
    end

    before { allow(PluginDirectory).to receive(:find_by_repo).and_return(nil) }

    it "installs the commit the directory pinned, not the latest release, and says so" do
      allow(PluginDirectory).to receive(:find_by_repo).with("acme/cms-thing").and_return(listed)
      release("thing.gemspec" => "", "lib/thing.rb" => "module Thing; end")
      allow(github).to receive(:download) do |url, path|
        expect(url).to eq("https://api.github.com/repos/acme/cms-thing/tarball/#{"c" * 40}")
        FileUtils.cp(@archive, path)
        path
      end

      change = described_class.install("acme/cms-thing", by: admin)
      perform_enqueued_jobs

      expect(change.reload).to have_attributes(pinned_commit: "c" * 40, to_version: "1.3.0", status: "running")
      expect(InstalledPlugins.metadata("thing")).to include("commit" => "c" * 40, "directory" => true, "version" => "1.3.0")
    end

    it "refuses one the directory says needs a newer CMS" do
      allow(PluginDirectory).to receive(:find_by_repo).and_return(listed.with(requires: ">= 99"))

      expect { described_class.install("acme/cms-thing", by: admin) }.to raise_error(described_class::Refused, /needs CMS >= 99/)
    end
  end

  describe "settling after the restart" do
    let!(:change) { described_class.create!(action: "install", repo: "acme/cms-thing", key: "thing", to_version: "1.2.0", requested_by: admin) }

    it "succeeds once the install runs the plugin at that release" do
      InstalledPlugins.loaded["thing"] = installed
      InstalledPlugins.versions["thing"] = "1.2.0"

      described_class.reconcile

      expect(change.reload.status).to eq("succeeded")
    end

    it "fails when the plugin didn't load, and an update puts the previous release back" do
      update = described_class.create!(action: "update", repo: "acme/cms-thing", key: "thing", from_version: "1.1.0", to_version: "1.2.0")
      installed.join("lib").mkpath
      InstalledPlugins.directory.join(".thing.previous/lib").mkpath
      InstalledPlugins.directory.join(".thing.previous/old.txt").write("1.1.0")
      InstalledPlugins.failed["thing"] = "NameError: boom"

      update.reconcile

      expect(update.reload).to have_attributes(status: "failed", message: "thing 1.2.0 didn't load (NameError: boom); 1.1.0 is back.")
      expect(installed.join("old.txt").read).to eq("1.1.0")
      expect(Cms::Restart).to have_received(:later)
    end

    it "fails at once, with what it said, when the restart after it failed, and an update goes back" do
      update = described_class.create!(action: "update", repo: "acme/cms-thing", key: "thing", from_version: "1.1.0", to_version: "1.2.0")
      installed.join("lib").mkpath
      InstalledPlugins.directory.join(".thing.previous").mkpath
      InstalledPlugins.directory.join(".thing.previous/old.txt").write("1.1.0")
      update.report.mkpath
      update.report.join("restart.log").write("Migrating to CreateThings\nActiveRecord::StatementInvalid: table things already exists\n")
      update.report.join("exit_status").write("1\n")

      described_class.reconcile

      expect(update.reload).to have_attributes(status: "failed",
        message: a_string_matching(/restart after updating thing to 1\.2\.0 failed \(exit 1\).*table things already exists/m))
      expect(installed.join("old.txt").read).to eq("1.1.0")
    end

    it "waits on a restart that hasn't finished, or finished well" do
      change.report.mkpath
      described_class.reconcile
      expect(change.reload).to be_running

      change.report.join("exit_status").write("0\n")
      described_class.reconcile
      expect(change.reload).to be_running
    end

    it "gives up on one that went quiet" do
      change.update_columns(created_at: 20.minutes.ago)

      described_class.reconcile

      expect(change.reload).to have_attributes(status: "failed", message: a_string_matching(/No word/))
    end
  end

  describe "updating and removing" do
    before do
      installed.mkpath
      installed.join("thing.gemspec").write("")
      installed.join(InstalledPlugins::METADATA).write({repo: "acme/cms-thing", version: "1.1.0"}.to_json)
      InstalledPlugins.versions["thing"] = "1.1.0"
    end

    it "updates to the newest release, and refuses when it already runs it" do
      expect(described_class.update_plugin("thing", by: admin)).to have_attributes(action: "update", from_version: "1.1.0")

      described_class.running.update_all(status: "succeeded")
      InstalledPlugins.versions["thing"] = "1.2.0"
      expect { described_class.update_plugin("thing", by: admin) }.to raise_error(described_class::Refused, /already at its newest/)
    end

    it "removes the code, keeps it aside, and restarts" do
      change = described_class.remove("thing", by: admin)
      perform_enqueued_jobs

      expect(change.reload.status).to eq("running")
      expect(installed).not_to exist
      expect(InstalledPlugins.directory.join(".thing.previous")).to exist
      expect(Cms::Restart).to have_received(:later)
    end

    it "removes its data too when asked: its tables, its migrations' record and its settings" do
      installed.join("db/migrate").mkpath
      installed.join("db/migrate/20990101000000_create_thing_widgets.rb").write("")
      connection = ActiveRecord::Base.connection
      connection.create_table(:thing_widgets) { it.string :name }
      connection.execute("INSERT INTO schema_migrations (version) VALUES ('20990101000000')")
      Setting.set("thing_options", {"color" => "blue"})
      Setting.set(Cms::Plugins::SETUP_KEY, {"thing" => Time.current.iso8601})

      change = described_class.remove("thing", by: admin, purge_data: true)
      perform_enqueued_jobs

      expect(change.reload).to have_attributes(summary: "Removing thing and its data", message: "Dropped thing_widgets.")
      expect(connection.table_exists?(:thing_widgets)).to be(false)
      expect(connection.select_values("SELECT version FROM schema_migrations")).not_to include("20990101000000")
      expect(Setting.find_by(key: "thing_options")).to be_nil
      expect(Setting.get(Cms::Plugins::SETUP_KEY)).not_to have_key("thing")
    ensure
      connection&.drop_table(:thing_widgets, if_exists: true)
    end

    it "keeps the data of a plugin the image has a copy of" do
      Rails.root.join("plugins/thing").tap(&:mkpath).join("thing.gemspec").write("")

      expect { described_class.remove("thing", by: admin, purge_data: true) }.to raise_error(described_class::Refused, /data stays/)
    ensure
      FileUtils.rm_rf(Rails.root.join("plugins/thing"))
    end

    it "leaves the image's plugins in it: they're switched off, not removed" do
      expect { described_class.remove("hello", by: admin) }.to raise_error(described_class::Refused, /switch it off/)
    end

    it "is done removing once the image's copy runs again" do
      change = described_class.create!(action: "remove", repo: "acme/cms-thing", key: "thing")
      InstalledPlugins.loaded["thing"] = Rails.root.join("plugins/thing")
      InstalledPlugins.origins["thing"] = :image

      change.reconcile

      expect(change.reload).to be_succeeded
    end
  end

  describe "updating a plugin the image brought" do
    let(:image) { Pathname(Dir.mktmpdir("image")).join("thing").tap(&:mkpath) }

    before do
      image.join("thing.gemspec").write(%(spec.version = "1.1.0"))
      image.join(InstalledPlugins::METADATA).write({repo: "acme/cms-thing", version: "1.1.0"}.to_json)
      InstalledPlugins.loaded["thing"] = image
      InstalledPlugins.versions["thing"] = "1.1.0"
      InstalledPlugins.origins["thing"] = :image
    end

    after { FileUtils.rm_rf(image.parent) }

    it "puts the newer release in the data directory, beside the image's copy" do
      plugin_release

      change = described_class.update_plugin("thing", by: admin)
      perform_enqueued_jobs

      expect(change.reload).to have_attributes(status: "running", from_version: "1.1.0", to_version: "1.2.0")
      expect(installed.join("lib/thing.rb")).to exist
      expect(image.join("thing.gemspec")).to exist
    end

    it "goes back to the image's copy when the release won't load" do
      change = described_class.create!(action: "update", repo: "acme/cms-thing", key: "thing", from_version: "1.1.0", to_version: "1.2.0")
      installed.join("lib").mkpath
      InstalledPlugins.failed["thing"] = "NameError: boom"

      change.reconcile

      expect(change.reload).to be_failed
      expect(installed).not_to exist
    end
  end
end
