# frozen_string_literal: true

# One plugin installed, updated or removed from Settings › Plugins.
# Plugins installed this way live on the server, in
# CMS_DATA_DIR/plugins (InstalledPlugins), each the latest release of a
# public GitHub repository. Installing or updating downloads that release,
# puts it in place and restarts the install (Cms::Restart), which loads it and
# runs its migrations on the way up; removing deletes its code and restarts,
# leaving its tables and data for a reinstall. A plugin updates only when
# someone presses its Update button. The change succeeds once the install
# boots with the plugin loaded at that release (or gone); an update that won't
# load puts the previous release back.
#
# Plugins in plugins/ (CMS_PLUGINS, bin/rails plugins:install) and engines/
# are bundled with the install's image or checkout and aren't changed here.
class PluginChange < ApplicationRecord
  include Eventable

  class Refused < StandardError; end
  class Failed < StandardError; end

  ACTIONS = %w[install update remove].freeze
  STATUSES = %w[running succeeded failed].freeze
  TIMEOUT = 15.minutes
  REPO_FORMAT = %r{\A[\w.-]+/[\w.-]+\z}
  NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/

  # Optional only so deleting the person keeps the record of what they did.
  belongs_to :requested_by, class_name: "User", optional: true

  normalizes :repo, with: ->(value) { value.to_s.strip.sub(%r{\A(https?://)?(www\.)?github\.com/}, "").delete_suffix("/").delete_suffix(".git") }

  validates :action, inclusion: {in: ACTIONS}
  validates :status, inclusion: {in: STATUSES}
  validates :repo, format: {with: REPO_FORMAT, message: "should be a GitHub repository, like owner/name"}

  scope :running, -> { where(status: "running") }
  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  def self.current = running.ordered.first

  def self.install(repo, by:) = start(action: "install", repo: repo, by: by)

  def self.update_plugin(key, by:)
    repo = installed_repo(key)
    running = InstalledPlugins.versions[key.to_s]
    latest = UpdateCheck::Github.new(repo: repo).get("releases/latest")["tag_name"].to_s.delete_prefix("v")
    raise Refused, "#{key} is already at its newest release (#{running})." if latest == running

    start(action: "update", key: key.to_s, repo: repo, from_version: running, by: by)
  rescue UpdateCheck::Github::Error => error
    raise Refused, error.message
  end

  def self.remove(key, by:)
    start(action: "remove", key: key.to_s, repo: installed_repo(key), from_version: InstalledPlugins.versions[key.to_s], by: by)
  end

  def self.start(by:, **attributes)
    raise Refused, "#{current.summary} is under way; try once it's done." if current
    raise Refused, "The CMS is updating to #{Upgrade.current.to_version}; try once it's done." if Upgrade.current

    create!(requested_by: by, **attributes).tap do |change|
      change.track_event(:started, action: change.action, repo: change.repo, key: change.key)
      PluginChangeJob.perform_later(change)
    end
  end

  # Settles running changes once the install has restarted. Called by
  # Settings › Plugins.
  def self.reconcile = running.find_each(&:reconcile)

  def self.installed_repo(key)
    InstalledPlugins.metadata(key.to_s)["repo"] or
      raise Refused, "#{key} wasn't installed from Settings › Plugins, so it's updated and removed by hand."
  end

  # Run by PluginChangeJob. True once the change is in place and waits on the restart.
  def perform(restart: true)
    (action == "remove") ? take_out : put_in(latest_tag)
    Cms::Restart.later(report: report) if restart
    true
  rescue Failed, UpdateCheck::Github::Error, SystemCallError, RuntimeError, JSON::ParserError => error
    fail_with error.message
    false
  ensure
    FileUtils.rm_rf(scratch) if @scratch
  end

  def reconcile
    if restart_failed?
      roll_back
      fail_with "The restart after #{summary.downcase_first} failed (exit #{report.join("exit_status").read.strip}):\n#{restart_output}"
    elsif InstalledPlugins.failed[key] && action != "remove"
      roll_back
      fail_with "#{key} #{to_version} didn't load (#{InstalledPlugins.failed[key]})#{"; #{from_version} is back" if action == "update"}."
    elsif done?
      update!(status: "succeeded", finished_at: Time.current)
    elsif created_at < TIMEOUT.ago
      fail_with "No word after #{TIMEOUT.inspect}. The install's log, or #{report.join("restart.log")}, says what happened."
    end
  end

  def fail_with(message)
    update!(status: "failed", finished_at: Time.current, message: message)
  end

  # Where the restart after it says how it went (Cms::Restart.later).
  def report = Cms.data_dir.join("plugin_changes", id.to_s)

  def running? = status == "running"
  def succeeded? = status == "succeeded"
  def failed? = status == "failed"

  def summary
    name = key || repo
    case action
    when "install" then "Installing #{name}"
    when "update" then "Updating #{name} to #{to_version || "its newest release"}"
    else "Removing #{name}"
    end
  end

  # How the audit log names it.
  def title = summary

  private

  def github = UpdateCheck::Github.new(repo: repo)
  def target = InstalledPlugins.directory.join(key)
  def previous = InstalledPlugins.directory.join(".#{key}.previous")
  def scratch = @scratch ||= InstalledPlugins.directory.join(".download-#{id}").tap { FileUtils.mkdir_p(it) }

  def restart_failed?
    status = report.join("exit_status")
    status.file? && status.read.strip.then { it.present? && it != "0" }
  end

  def restart_output = report.join("restart.log").then { it.file? ? it.readlines.last(20).join : "(no output)" }

  def done?
    if action == "remove"
      !InstalledPlugins.loaded.key?(key)
    else
      InstalledPlugins.loaded.key?(key) && InstalledPlugins.versions[key] == to_version
    end
  end

  def latest_tag
    github.get("releases/latest")["tag_name"].presence or raise Failed, "#{repo} has no release to install."
  end

  # Downloads the release, checks it's a plugin, and swaps it in. The one it
  # replaces stays beside it until the next change, to roll back to.
  def put_in(tag)
    update!(to_version: tag.delete_prefix("v"))
    archive = github.download("https://api.github.com/repos/#{repo}/tarball/#{tag}", scratch.join("plugin.tar.gz"))
    unpacked = scratch.join("plugin").tap { FileUtils.mkdir_p(it) }
    system("tar", "-xzf", archive.to_s, "-C", unpacked.to_s, "--strip-components=1", "--no-same-owner", exception: true)

    gemspec = unpacked.glob("*.gemspec").first or raise Failed, "#{repo} #{tag} isn't a CMS plugin: it has no gemspec at its root."
    name = gemspec.basename(".gemspec").to_s
    raise Failed, "#{repo} names its plugin #{name}, which isn't a plain lowercase name." unless name.match?(NAME_FORMAT)
    raise Failed, "#{repo} holds the #{name} plugin, not #{key}." if key && key != name
    raise Failed, "#{name} is already installed. Update or remove it instead." if action == "install" && InstalledPlugins.present.key?(name)
    raise Failed, "#{name} comes with this install (plugins/ or engines/), so it's changed there." if Gem.loaded_specs.key?(name)

    update!(key: name)
    unpacked.join(InstalledPlugins::METADATA).write({repo: repo, version: to_version, tag: tag, installed_at: Time.current.iso8601}.to_json)
    FileUtils.rm_rf(previous)
    File.rename(target, previous) if target.exist?
    File.rename(unpacked, target)
  end

  def take_out
    raise Failed, "#{key} isn't installed." unless target.exist?

    FileUtils.rm_rf(previous)
    File.rename(target, previous)
    Cms::Plugins.switch!(key, on: false) if Cms::Plugins.manifests.key?(key.to_sym)
  end

  def roll_back
    return unless action == "update" && previous.exist?

    FileUtils.rm_rf(target)
    File.rename(previous, target)
    Cms::Restart.later
  end
end
