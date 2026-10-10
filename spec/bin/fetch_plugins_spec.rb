# frozen_string_literal: true

require "rails_helper"
require "open3"

# bin/fetch-plugins, run for real in a stand-in app against a local plugin
# repository with two commits.
RSpec.describe "bin/fetch-plugins" do
  let(:root) { Pathname(Dir.mktmpdir("fetch-plugins")) }
  let(:app) { root.join("app") }
  let(:repo) { root.join("cms-thing") }

  after { root.rmtree }

  before do
    app.join("bin").mkpath
    app.join("config").mkpath
    app.join("plugins").mkpath
    FileUtils.cp(Rails.root.join("bin/fetch-plugins"), app.join("bin/fetch-plugins"))

    git = ->(*args) { system("git", "-C", repo.to_s, *args, out: File::NULL, err: File::NULL) or raise "git #{args.join(" ")}" }
    repo.mkpath
    git.call("init", "--quiet", "--initial-branch", "main")
    repo.join("thing.gemspec").write("# first\n")
    git.call("add", ".")
    git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-m", "first")
    repo.join("thing.gemspec").write("# second\n")
    git.call("-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-am", "second")
  end

  def commit(ref) = `git -C #{repo} rev-parse #{ref}`.strip

  def fetch(defaults)
    app.join("config/default_plugins.yml").write(defaults.to_yaml)
    Open3.capture2e({"CMS_PLUGINS" => ""}, app.join("bin/fetch-plugins").to_s)
  end

  it "fetches a default pinned to a commit at that commit, with no git history" do
    output, status = fetch("thing" => "file://#{repo}##{commit("HEAD~1")}")

    expect(status).to be_success, output
    expect(app.join("plugins/thing/thing.gemspec").read).to eq("# first\n")
    expect(app.join("plugins/thing/.git")).not_to exist
  end

  it "fetches the default branch when no ref is given" do
    output, status = fetch("thing" => "file://#{repo}")

    expect(status).to be_success, output
    expect(app.join("plugins/thing/thing.gemspec").read).to eq("# second\n")
  end

  it "stops the build when it can't fetch a pinned commit" do
    output, status = fetch("thing" => "file://#{repo}##{"0" * 40}")

    expect(status).not_to be_success
    expect(output).to include("Couldn't clone")
  end
end
