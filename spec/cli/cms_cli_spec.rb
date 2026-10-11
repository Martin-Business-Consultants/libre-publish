# frozen_string_literal: true

require "json"
require "tmpdir"
require "open3"
require "fileutils"

# The `cms` CLI is a single stdlib-only Ruby file, so it can be exercised as
# itself rather than through Rails. What is worth pinning here is the part an
# agent depends on and a person never looks at: the catalogue. It is the one
# description of the surface, and the dispatcher runs from the same table, so a
# command missing its usage or notes is a command an agent will misuse.
RSpec.describe "cms CLI" do
  CLI = File.expand_path("../../agent/cms", __dir__)

  # No credentials in the environment, so a command that tries to reach a server
  # fails predictably instead of picking up the developer's own profile.
  def run(*args)
    stdout, stderr, status = Open3.capture3(
      {"CMS_URL" => "", "USER_AGENT_TOKEN" => "", "CMS_TOKEN" => "", "CMS_PROFILE" => "",
       "XDG_CONFIG_HOME" => Dir.mktmpdir},
      "ruby", CLI, *args
    )
    [stdout, stderr, status.exitstatus]
  end

  def catalogue
    stdout, = run("commands", "--json")
    JSON.parse(stdout).fetch("data")
  end

  it "describes its whole surface in one call" do
    data = catalogue

    expect(data["commands"].size).to be > 50
    expect(data["global_flags"].map { |f| f["flag"] }).to include("--agent", "--profile NAME")
  end

  it "gives every command a name, a summary and a usage line" do
    catalogue["commands"].each do |command|
      expect(command["name"]).not_to be_empty
      expect(command["summary"].to_s).not_to be_empty, "#{command["name"]} has no summary"
      expect(command["usage"]).to start_with("cms "), "#{command["name"]} has no usage line"
    end
  end

  # The catalogue and the dispatcher read the same table, so this is really
  # asserting that nothing in it is unreachable.
  it "answers --help for every command it lists" do
    catalogue["commands"].each do |command|
      stdout, _stderr, status = run(command["name"], "--help")
      expect(status).to eq(0), "cms #{command["name"]} --help exited #{status}"
      expect(stdout).to include(command["usage"])
    end
  end

  it "keeps an escape hatch for anything the curated commands miss" do
    names = catalogue["commands"].map { |c| c["name"] }

    expect(names).to include("get", "post", "patch", "delete")
  end

  describe "without credentials" do
    it "says how to get them rather than failing obscurely" do
      _stdout, stderr, status = run("pages")

      expect(status).to eq(1)
      expect(stderr).to include("cms login")
    end

    it "names the profile that is missing, when one was asked for" do
      _stdout, stderr, = run("--profile", "acme", "pages")

      expect(stderr).to include("no profile named 'acme'")
      expect(stderr).to include("--profile acme")
    end

    # `cms login` is what creates a profile, so it must not be blocked by that
    # profile not existing yet.
    it "still lets login run for a profile that does not exist yet" do
      _stdout, stderr, = run("login", "--profile", "acme")

      expect(stderr).not_to include("no profile named")
    end
  end

  # A desktop app runs what `cms connect` prints with none of the shell's PATH,
  # so the command must stand on its own, on the right site.
  describe "connect" do
    def connect(*args, env: {})
      config = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(config, "cms"))
      %w[acme other].each do |name|
        File.write(File.join(config, "cms", "#{name}.env"), %(export CMS_URL="https://#{name}.test"\nexport USER_AGENT_TOKEN="lp_x"\n))
      end
      stdout, = Open3.capture3({"CMS_URL" => "", "USER_AGENT_TOKEN" => "", "CMS_TOKEN" => "", "CMS_PROFILE" => "",
                                "CMS_BIN" => nil, "XDG_CONFIG_HOME" => config, **env},
                               "ruby", CLI, "connect", *args, "--agent")
      JSON.parse(stdout).fetch("data")
    end

    it "pins the profile, and names the server after it when there are several" do
      server = connect("--profile", "acme", env: {"CMS_BIN" => "/opt/cms/bin/cms"})["server"]

      expect(server).to include("name" => "cms-acme", "command" => "/opt/cms/bin/cms", "args" => %w[--profile acme mcp],
                                "url" => "https://acme.test")
    end

    it "names the Ruby running it when it wasn't started through the installer's command" do
      server = connect("--profile", "acme")["server"]

      expect(server["command"]).to end_with("ruby")
      expect(server["args"]).to eq([CLI, "--profile", "acme", "mcp"])
    end

    it "gives the setup for one app when asked" do
      clients = connect("codex", "--profile", "acme", env: {"CMS_BIN" => "/opt/cms/bin/cms"})["clients"]

      expect(clients.map { it["client"] }).to eq(%w[codex])
      expect(clients.first["setup"]).to include("codex mcp add cms-acme -- /opt/cms/bin/cms --profile acme mcp")
    end
  end

  it "refuses an unknown command with a pointer to the catalogue" do
    _stdout, stderr, status = run("frobnicate")

    expect(status).to eq(1)
    expect(stderr).to include("cms commands")
  end

  it "prints a usage screen grouped by what things are for" do
    stdout, = run("help")

    expect(stdout).to include("Setup", "Content", "Publishing")
    expect(stdout).to include("cms doctor")
  end
end
