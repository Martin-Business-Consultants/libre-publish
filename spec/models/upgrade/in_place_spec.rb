# frozen_string_literal: true

require "rails_helper"

# A release's bundle is built here as the release workflow builds it (a tar
# of the app with its VERSION and plugins), into a data directory of its own.
# GitHub and the container's restart are stood in for.
RSpec.describe Upgrade::InPlace do
  include ActiveJob::TestHelper

  let(:data_dir) { Pathname(Dir.mktmpdir("cms-data")) }
  let(:releases) { data_dir.join("releases") }
  let(:upgrade) { Upgrade.create!(requested_by: create(:user), from_version: Cms::VERSION, to_version: "99.0.0", via: "in_place") }
  let(:github) { instance_double(UpdateCheck::Github) }
  let(:arch) { described_class.arch }
  let(:bundle_name) { "cms-v99.0.0-linux-#{arch}.tar.gz" }

  around { |example| with_env("CMS_DATA_DIR" => data_dir.to_s, "CMS_BASE" => "1", "CMS_RUNTIME" => "docker") { example.run } }
  after { data_dir.rmtree }

  before do
    allow(UpdateCheck::Github).to receive(:new).and_return(github)
    allow(Cms::Restart).to receive(:container_later)
  end

  # The release on GitHub: its manifest, its bundle and the bundle's checksum.
  def release(version: "99.0.0", base: "1", plugins: plugins_here, checksum: nil, assets: nil)
    dir = Pathname(Dir.mktmpdir("bundle"))
    app = dir.join("app").tap(&:mkpath)
    app.join("VERSION").write("#{version}\n")
    plugins.each { app.join("plugins", it).tap(&:mkpath).join("#{it}.gemspec").write("") }
    archive = dir.join(bundle_name)
    system("tar", "-czf", archive.to_s, "-C", app.to_s, ".", exception: true)
    files = {
      "cms-v99.0.0.json" => {version:, ruby: RUBY_VERSION, base:, bundles_ruby: true}.to_json,
      bundle_name => archive.binread,
      "#{bundle_name}.sha256" => "#{checksum || Digest::SHA256.file(archive).hexdigest}  #{bundle_name}\n"
    }
    names = assets || files.keys
    allow(github).to receive(:get).with("releases/tags/v99.0.0").and_return("assets" => names.map { {"name" => it, "browser_download_url" => "https://example.test/#{it}"} })
    allow(github).to receive(:download) do |url, path|
      Pathname(path).binwrite(files.fetch(File.basename(url)))
      path
    end
  end

  def plugins_here = Rails.root.glob("plugins/*/*.gemspec").map { it.basename(".gemspec").to_s }

  it "starts away from the request, in a job" do
    described_class.new(upgrade).start

    expect(Upgrade::InstallJob).to have_been_enqueued.with(upgrade)
  end

  it "puts the release's bundle in the data volume, points current at it and restarts the container" do
    release
    releases.join("v1.0.0").mkpath
    releases.join("v2.0.0").mkpath

    described_class.new(upgrade).install

    expect(releases.join("v99.0.0/VERSION").read).to eq("99.0.0\n")
    expect(releases.join("current").readlink.to_s).to eq("v99.0.0")
    expect(releases.children.map { it.basename.to_s }.sort).to eq(%w[current v2.0.0 v99.0.0])
    expect(Cms::Restart).to have_received(:container_later)
    expect(upgrade.reload).to be_running
  end

  it "leaves it be when it runs again after the restart on the new version" do
    upgrade.update!(to_version: Cms::VERSION)

    described_class.new(upgrade).install

    expect(upgrade.reload).to be_succeeded
    expect(Cms::Restart).not_to have_received(:container_later)
  end

  it "changes nothing when the bundle isn't there yet, doesn't match its checksum, or holds another version" do
    release(assets: ["cms-v99.0.0.json"])
    described_class.new(upgrade).install
    expect(upgrade.reload.message).to match(/has no #{Regexp.escape(bundle_name)} yet/)

    upgrade.update!(status: "running", message: nil)
    release(checksum: "0" * 64)
    described_class.new(upgrade).install
    expect(upgrade.reload.message).to match(/didn't match its checksum/)

    upgrade.update!(status: "running", message: nil)
    release(version: "98.0.0")
    described_class.new(upgrade).install
    expect(upgrade.reload.message).to match(/holds 98.0.0, not 99.0.0/)

    expect(releases.join("current")).not_to exist
    expect(releases.children.map { it.basename.to_s }).to be_empty
    expect(Cms::Restart).not_to have_received(:container_later)
  end

  it "fails the update with why, when the release didn't start and the install went back to its image" do
    releases.mkpath
    releases.join("v99.0.0.failed").write("NoMethodError: it broke\n")

    described_class.new(upgrade).check

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to include("v99.0.0 didn't start", "went back to #{Cms::VERSION}", "NoMethodError: it broke")
  end

  it "won't leave behind a plugin the image carries that the bundle doesn't" do
    allow(Rails.root).to receive(:glob).and_call_original
    allow(Rails.root).to receive(:glob).with("plugins/*/*.gemspec").and_return([Pathname("/rails/plugins/cms-seo/seo.gemspec")])
    release(plugins: [])

    described_class.new(upgrade).install

    expect(upgrade.reload).to be_failed
    expect(upgrade.message).to include("carries seo (CMS_PLUGINS)", "Settings › Plugins", "Nothing was changed")
    expect(releases.join("current")).not_to exist
  end

  it "redeploys through a strategy that can when the release needs a new base, or says how" do
    release(base: "2")
    described_class.new(upgrade).install
    expect(upgrade.reload.message).to include("needs a new image, for base 2 (this image has 1)", "Redeploy it")

    upgrade.update!(status: "running", message: nil)
    deployer = register_update_strategy("deployer")
    described_class.new(upgrade).install
    expect(upgrade.reload).to have_attributes(via: "deployer", status: "running")
    expect(upgrade.message).to include("deploying it through Deployer")
    expect(deployer.started).to be(true)
  end
end
