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
# switches to it), so a new Ruby comes this way too.
#
# Without downtime, when it can: with Puma's workers running from the
# releases/live symlink (bin/docker-entrypoint, config/puma.rb), a release on
# the same Ruby and Puma is backed up and migrated while the running one
# serves, live is pointed at it, and the workers restart onto it one at a
# time (lib/puma/plugin/cms_restart.rb). One that hasn't taken over a few
# minutes later is switched back. Otherwise, as before: the container
# restarts onto it. A release that needs
# other system packages or Debian (CMS_BASE in the Dockerfile) can't: it
# redeploys through Upgrade.redeployer when there is one, else fails with how.
# Plugins installed from Settings › Plugins live in the data volume and carry
# over. One only the image carries (CMS_PLUGINS, the CMS_THEME theme) is
# copied there first, so the release keeps running it (InstalledPlugins).
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

    archive = download
    return unless still_wanted?

    unpack(archive)
    return unless still_wanted?

    if seamless?
      switch_without_downtime
    else
      switch
      prune
      Cms::Restart.container_later
    end
  rescue Failed, UpdateCheck::Github::Error, SystemCallError, RuntimeError, JSON::ParserError => error
    @upgrade.fail_with(error.message)
  ensure
    FileUtils.rm_rf(@scratch) if @scratch
  end

  # The job reports its own failure. A release that wouldn't start sent the
  # install back to its image (bin/docker-entrypoint), leaving why in
  # releases/<tag>.failed; a restart that never comes back is the timeout's.
  def check
    return switch_back_if_stuck if seamless_note.file?

    failed = self.class.releases.join("#{tag}.failed")
    return unless failed.file?

    @upgrade.fail_with("#{tag} didn't start, so this install went back to #{Cms::VERSION}:\n#{failed.read.lines.last(20).join}")
  end

  # How long new workers have to come up on a release switched to without
  # downtime before it's switched back.
  TAKEOVER = 5.minutes

  def timing_out_since = @upgrade.created_at

  # Not stopped from Settings › Updates while the download ran.
  def still_wanted? = @upgrade.reload.running?

  def where_to_look = "The container's log says what happened."

  private

  def tag = @upgrade.tag
  def live = Pathname(ENV["CMS_APP_DIR"].to_s)
  def seamless_note = self.class.releases.join(".seamless.json")

  # Puma's workers run from the live symlink, and the release runs on this
  # Ruby and this Puma (Puma's parent stays as it is).
  def seamless?
    return false unless ENV["CMS_PUMA_CLUSTERED"] == "1" && live.to_s.present? && live.symlink?

    manifest = JSON.parse(scratch.join("manifest.json").read) rescue {}
    manifest["ruby"].to_s == RUBY_VERSION && puma_version(directory) == puma_version(Rails.root) && puma_version(Rails.root)
  end

  def puma_version(root)
    lock = root.join("Gemfile.lock")
    lock.read[/^    puma \(([^)]+)\)/, 1] if lock.file?
  end

  # Backs up and migrates with the release's own code, while this one
  # serves; then points live (and current, for the container's next start)
  # at it and asks Puma's workers to restart onto it, one at a time.
  def switch_without_downtime
    prepare_release!
    previous = live.realpath
    switch
    point(live, directory)
    seamless_note.write({tag: tag, previous: previous.to_s, at: Time.current.iso8601}.to_json)
    directory.join("tmp").mkpath
    FileUtils.touch(directory.join("tmp", "restart.txt"))
    @upgrade.update!(message: "#{tag} is ready; the site's workers are moving onto it one at a time, with no downtime.")
  end

  # The image's Bundler settings (BUNDLE_WITHOUT above all: the bundle holds
  # no development or test gems) go along, as the unbundled env drops them.
  def prepare_release!
    log = self.class.releases.join(".prepare.log")
    env = ENV.slice("BUNDLE_WITHOUT", "BUNDLE_WITH", "BUNDLE_DEPLOYMENT").merge(
      "BUNDLE_GEMFILE" => directory.join("Gemfile").to_s, "BUNDLE_PATH" => directory.join("bundle").to_s,
      "CMS_BUNDLED_RUBY" => RbConfig.ruby, "CMS_DATA_DIR" => Cms.data_dir.to_s)
    ok = run_preparation(env, "./bin/rails cms:backup_if_pending && ./bin/rails db:migrate", log)
    raise Failed, "#{tag} couldn't be prepared, so nothing was switched:\n#{log.file? ? log.read.lines.last(20).join : "(no output)"}" unless ok
  end

  def run_preparation(env, command, log)
    Bundler.with_unbundled_env do
      system(env, "bash", "-c", command, chdir: directory.to_s, out: log.to_s, err: [:child, :out])
    end
  end

  # A new link beside the old, renamed over it.
  def point(link, target)
    fresh = link.dirname.join(".#{link.basename}.next")
    FileUtils.rm_f(fresh)
    File.symlink(target.to_s, fresh.to_s)
    File.rename(fresh, link)
  end

  # Checked from Settings › Updates and the daily job: a release switched to
  # without downtime whose workers haven't taken over in TAKEOVER goes back.
  def switch_back_if_stuck
    note = JSON.parse(seamless_note.read)
    return seamless_note.delete if note["tag"] != tag || Cms.version >= Gem::Version.new(@upgrade.to_version)
    return if Time.zone.parse(note["at"]) > TAKEOVER.ago

    previous = Pathname(note["previous"])
    point(live, previous) if live.symlink?
    image = Pathname(ENV["CMS_IMAGE_ROOT"].presence || "/rails")
    (image.exist? && previous.realpath == image.realpath) ? FileUtils.rm_f(self.class.releases.join("current")) : point(self.class.releases.join("current"), previous)
    seamless_note.delete
    FileUtils.touch(previous.join("tmp", "restart.txt")) if previous.join("tmp").directory?
    @upgrade.fail_with("#{tag}'s workers didn't come up within #{TAKEOVER.inspect}, so this install went back to #{Cms::VERSION}. " \
                       "The container's log says why.")
  end
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

    carry_over(partial)

    FileUtils.rm_rf(directory)
    File.rename(partial, directory)
  ensure
    FileUtils.rm_rf(partial) if partial&.exist?
  end

  # The plugins and theme this install runs from its image that the bundle
  # doesn't bring, copied into the data directory with where they came from,
  # where the release finds them (and Settings › Plugins can update them).
  def carry_over(release)
    bundled = InstalledPlugins.plugins_in(release.join("plugins")).map { it[:name] }
    InstalledPlugins.loaded.each do |name, path|
      next unless InstalledPlugins.origins[name] == :image && !bundled.include?(name)

      copy = InstalledPlugins.directory.join(name)
      next if copy.exist?

      FileUtils.mkdir_p(InstalledPlugins.directory)
      FileUtils.cp_r(path, InstalledPlugins.directory.join(".#{name}.carrying"))
      File.rename(InstalledPlugins.directory.join(".#{name}.carrying"), copy)
    end
  end

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
    # Never the release running, nor the one whose Ruby Puma's parent runs on
    # (a switch without downtime keeps it: config/bundled_ruby.rb).
    ruby_home = ENV["CMS_BUNDLED_RUBY"].presence && Pathname(ENV["CMS_BUNDLED_RUBY"]).dirname.dirname.dirname
    (releases - kept - [Rails.root, ruby_home].compact).each { FileUtils.rm_rf(it) }
  end

  def scratch = @scratch ||= self.class.releases.join(".download-#{@upgrade.id}").tap { FileUtils.mkdir_p(it) }
end
