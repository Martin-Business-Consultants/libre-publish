# frozen_string_literal: true

# One update of this install to a newer release, started by an admin from
# Settings › Updates. How it happens depends on how the install runs
# (`Upgrade.via`):
#
#   github  a Docker install deployed with Kamal: starts the releases repo's
#           Deploy workflow (.github/workflows/deploy.yml) for this install's
#           destination (Upgrade::Github)
#   local     a plain install (bin/install): runs bin/update with the release's
#             tag in the background, which restarts Puma when it's done
#             (Upgrade::Local)
#   in_place  any other Docker install: downloads the release's bundle into
#             its data volume and restarts on it, the way WordPress updates
#             itself (Upgrade::InPlace)
#   manual    none of these: Settings › Updates shows the command instead
#
# A plugin adds others (Cms::Plugins.update_strategy, docs/plugins.md) — a
# deploy tool the install runs under, say. CMS_UPDATES picks one. Left unset,
# a production checkout with a .env is local, then the first plugin strategy
# that says it's configured, then github with CMS_GITHUB_TOKEN, and any other
# Docker install (CMS_RUNTIME=docker) is in_place; anything else, development
# included, is manual, so a button never checks
# out a tag over someone's working copy. It succeeds when this install boots on the new
# version; a failed run, or no word within TIMEOUT, fails it. The old version
# keeps running meanwhile.
class Upgrade < ApplicationRecord
  include Eventable

  class Refused < StandardError; end
  # What a runner raises when the place it updates through answers badly; the
  # update fails with its message (a plugin's runner subclasses it).
  class Error < StandardError; end

  # The runners that ship with the core; plugins add theirs (`runners`).
  CORE_RUNNERS = {"github" => "Upgrade::Github", "local" => "Upgrade::Local", "in_place" => "Upgrade::InPlace"}.freeze
  STATUSES = %w[running succeeded failed].freeze
  TIMEOUT = 45.minutes

  # Optional only so deleting the person keeps the record of what they did.
  belongs_to :requested_by, class_name: "User", optional: true

  validates :requested_by, presence: true, on: :create
  # Checked as an update starts: afterwards it's the record of how it ran, kept
  # even when the plugin whose strategy it was is removed.
  validates :via, inclusion: {in: ->(_) { runners.keys }}, on: :create
  validates :status, inclusion: {in: STATUSES}

  scope :running, -> { where(status: "running") }
  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  # Every way this install could be updated: via => runner class.
  def self.runners = CORE_RUNNERS.transform_values(&:constantize).merge(Cms::Plugins.enabled_update_strategies)

  def self.vias = runners.keys + ["manual"]

  # The plugins' runners that can deploy a new image of the install
  # (`redeploys?`), then GitHub's: what an in-place update falls back on.
  def self.redeployer
    plugins = Cms::Plugins.enabled_update_strategies.select { |_, runner| runner.try(:redeploys?) && runner.configured? }
    plugins.keys.first || ("github" if Upgrade::Github.configured?)
  end

  def self.via
    configured = ENV["CMS_UPDATES"].presence
    if vias.include?(configured)
      configured
    elsif !Rails.env.production?
      "manual"
    elsif Rails.root.join(".git").exist? && Rails.root.join(".env").exist?
      "local"
    elsif (plugin = Cms::Plugins.enabled_update_strategies.find { |_, runner| runner.configured? })
      plugin.first
    elsif UpdateCheck::Github.deploy_token?
      "github"
    elsif Upgrade::InPlace.available?
      "in_place"
    else
      "manual"
    end
  end

  # Why the button can't update this install, or nil when it can.
  def self.unavailable_reason
    runner = runners[via]
    return "Updating from here isn't set up on this install." unless runner

    runner.try(:unavailable_reason)
  end

  def self.available? = unavailable_reason.nil?

  def self.current = running.ordered.first

  # Updates the install to the latest release, as the person who asked.
  # Refuses when that release isn't newer, updating isn't set up, or an
  # update is already running.
  def self.start(by:)
    raise Refused, unavailable_reason unless available?
    raise Refused, "There's no newer release to update to." unless UpdateCheck.update_available?
    raise Refused, "An update to #{current.to_version} is already running." if current

    create!(requested_by: by, from_version: Cms::VERSION, to_version: UpdateCheck.latest_version, via: via).tap do |upgrade|
      upgrade.track_event(:started, from_version: upgrade.from_version, to_version: upgrade.to_version, via: upgrade.via)
      upgrade.run
    end
  end

  # Settles running updates: done once this install runs the new version,
  # failed when the run failed or went quiet. Called by Settings › Updates
  # and the daily check.
  def self.settle_running = running.find_each(&:settle)

  def run
    runner.start
  rescue Error, UpdateCheck::Github::Error, SystemCallError => error
    fail_with error.message
  end

  def settle
    if Cms.version >= Gem::Version.new(to_version)
      update!(status: "succeeded", finished_at: Time.current, message: nil)
    elsif (since = runner.timing_out_since) && since < TIMEOUT.ago
      fail_with "No word after #{TIMEOUT.inspect}. #{runner.where_to_look}"
    else
      runner.check
    end
  rescue Refused => error
    fail_with error.message
  rescue Error, UpdateCheck::Github::Error => error
    Rails.error.report(error, context: {upgrade: id})
  end

  def fail_with(message)
    update!(status: "failed", finished_at: Time.current, message: message)
  end

  def running? = status == "running"
  def succeeded? = status == "succeeded"
  def failed? = status == "failed"

  def tag = "v#{to_version}"

  # How the audit log names it.
  def title = "#{from_version} → #{to_version}"

  # The runner for how this update went. One started by a plugin that has
  # since been removed has none, and settles as failed.
  def runner
    runner = self.class.runners[via]
    raise Refused, "The #{via} update strategy isn't installed any more." unless runner

    runner.new(self)
  end
end
