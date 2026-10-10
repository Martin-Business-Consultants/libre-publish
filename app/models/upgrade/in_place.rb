# frozen_string_literal: true

require "digest"

# Updates a Docker install in place, the way WordPress updates itself:
# downloads the release's bundle (the app as its image holds
# it, gems, compiled assets and the default plugins included, built for each
# architecture by .github/workflows/release.yml) into releases/ in the data
# directory, checks it, points releases/current at it and restarts the
# container. On boot bin/docker-entrypoint runs whichever is newer, the image
# or releases/current, then backs up and migrates as always. Deploying a newer
# image takes over again.
#
# Each bundle carries the Ruby its gems were built for (config/bundled_ruby.rb
# switches to it), so a new Ruby comes this way too. A release that needs
# other system packages or Debian (CMS_BASE in the Dockerfile) can't: it
# redeploys through Upgrade.redeployer when there is one, else fails with how.
# Plugins installed from Settings › Plugins live in the data volume and carry
# over; one the image carries that the bundle doesn't (from CMS_PLUGINS)
# would be lost, so the update refuses and says so.
class Upgrade::InPlace
  class Failed < StandardError; end

  # The release running and the one before it, to go back to by hand.
  KEEP = 2

  def self.label = "In place"
  def self.description = "This install itself: it downloads the release and restarts on it"
  def self.available? = ENV["CMS_RUNTIME"] == "docker"
  def self.releases = Cms.data_dir.join("releases")
  def self.arch = RbConfig::CONFIG["host_cpu"].in?(%w[aarch64 arm64]) ? "arm64" : "amd64"

  def initialize(upgrade)
    @upgrade = upgrade
  end

  # Away from the request that asked: the download takes a while.
  def start = Upgrade::InstallJob.perform_later(@upgrade)

  # Run by Upgrade::InstallJob. A job that runs again after the restart finds
  # the new version running and leaves it.
  def install
    return @upgrade.settle if Cms.version >= Gem::Version.new(@upgrade.to_version)
    return if needs_image?(fetch_manifest)

    unpack(download)
    switch
    prune
    Cms::Restart.container_later
  rescue Failed, UpdateCheck::Github::Error, SystemCallError, RuntimeError, JSON::ParserError => error
    @upgrade.fail_with(error.message)
  ensure
    FileUtils.rm_rf(@scratch) if @scratch
  end

  # The job reports its own failure. A release that wouldn't start sent the
  # install back to its image (bin/docker-entrypoint), leaving why in
  # releases/<tag>.failed; a restart that never comes back is the timeout's.
  def check
    failed = self.class.releases.join("#{tag}.failed")
    return unless failed.file?

    @upgrade.fail_with("#{tag} didn't start, so this install went back to #{Cms::VERSION}:\n#{failed.read.lines.last(20).join}")
  end

  def timing_out_since = @upgrade.created_at

  def where_to_look = "The container's log says what happened."

  private

  def tag = @upgrade.tag
  def directory = self.class.releases.join(tag)
  def github = UpdateCheck::Github.new
  def assets = @assets ||= github.get("releases/tags/#{tag}")["assets"].to_a.to_h { [it["name"], it["browser_download_url"]] }

  def asset_url(name)
    assets[name] or raise Failed, "#{tag} has no #{name} yet. GitHub builds it in the minutes after a release; try again shortly."
  end

  def fetch_manifest
    JSON.parse(download_to("cms-#{tag}.json", scratch.join("manifest.json")).read)
  end

  # A bundle needs the same base as this image (its Ruby travels with it).
  # When it needs a new image, deploy one through a strategy that can
  # (Upgrade.redeployer: a plugin's deploy tool, or GitHub), else fail with how.
  def needs_image?(manifest)
    return false if manifest["base"].to_s == ENV["CMS_BASE"].to_s

    reason = "base #{manifest["base"]} (this image has #{ENV["CMS_BASE"].presence || "none"})"
    via = Upgrade.redeployer
    raise Failed, "#{tag} needs a new image, for #{reason}. Redeploy it: with your deploy tool, or `bin/kamal deploy` from a checkout of #{tag}. " \
                  "Data and plugins carry over; later updates come this way again." unless via

    @upgrade.update!(via: via, message: "#{tag} needs a new image, for #{reason}: deploying it through #{Upgrade.runners[via].label}.")
    @upgrade.runner.start
    true
  end

  def download
    name = "cms-#{tag}-linux-#{self.class.arch}.tar.gz"
    archive = download_to(name, scratch.join(name))
    expected = download_to("#{name}.sha256", scratch.join("#{name}.sha256")).read.split.first

    raise Failed, "#{name} didn't match its checksum. Nothing was changed." unless Digest::SHA256.file(archive).hexdigest == expected

    archive
  end

  def download_to(name, path) = Pathname(github.download(asset_url(name), path))

  def unpack(archive)
    FileUtils.rm_f(self.class.releases.join("#{tag}.failed")) # trying it again
    partial = self.class.releases.join(".#{tag}.partial")
    FileUtils.rm_rf(partial)
    FileUtils.mkdir_p(partial)
    system("tar", "-xzf", archive.to_s, "-C", partial.to_s, "--no-same-owner", exception: true)

    version = partial.join("VERSION").read.strip
    raise Failed, "The #{tag} bundle holds #{version}, not #{@upgrade.to_version}." unless version == @upgrade.to_version

    left_behind = plugins_in(Rails.root) - plugins_in(partial)
    if left_behind.any?
      raise Failed, "This install's image carries #{left_behind.to_sentence} (CMS_PLUGINS), which the #{tag} bundle doesn't, so updating " \
                    "here would leave #{left_behind.one? ? "it" : "them"} behind. Redeploy instead (with your deploy tool, or `bin/kamal deploy`), or " \
                    "install #{left_behind.one? ? "it" : "them"} from Settings › Plugins, where plugins carry over. Nothing was changed."
    end

    FileUtils.rm_rf(directory)
    File.rename(partial, directory)
  ensure
    FileUtils.rm_rf(partial) if partial&.exist?
  end

  def plugins_in(root) = root.glob("plugins/*/*.gemspec").map { it.basename(".gemspec").to_s }

  # Atomic: a new link beside the old, renamed over it.
  def switch
    link = self.class.releases.join("current")
    fresh = self.class.releases.join(".current")
    FileUtils.rm_f(fresh)
    File.symlink(tag, fresh)
    File.rename(fresh, link)
  end

  def prune
    releases = self.class.releases.glob("v*").select(&:directory?)
    kept = releases.sort_by { Gem::Version.new(it.basename.to_s.delete_prefix("v")) }.last(KEEP)
    (releases - kept - [Rails.root]).each { FileUtils.rm_rf(it) }
  end

  def scratch = @scratch ||= self.class.releases.join(".download-#{@upgrade.id}").tap { FileUtils.mkdir_p(it) }
end
