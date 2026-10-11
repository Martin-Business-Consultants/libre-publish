# frozen_string_literal: true

require "puma/plugin"

# Restarts without a visitor noticing (docs/install.md, Updates without
# downtime). `bin/rails restart`, a plugin or theme going live
# (Cms::Restart) or a release updated in place (Upgrade::InPlace), touches
# tmp/restart.txt; this sees it and restarts the workers one at a time (a
# phased restart), each loading the code at the app's directory — a symlink
# (CMS_APP_DIR) the update points at the new release — while the others go on
# serving. Without workers, Puma's ordinary restart.
#
# It also runs the background jobs, in clustered mode: Solid Queue's own Puma
# plugin forks them from Puma's parent, which here doesn't load the app. They
# run as a process of their own (bin/jobs, from the app's directory), started
# after Puma boots, started again with each restart (so they run the new code
# too), and stopped with Puma.
Puma::Plugin.create do
  def start(launcher)
    @launcher = launcher
    @jobs = launcher.options[:workers].to_i.positive? && ENV["SOLID_QUEUE_IN_PUMA"].to_s.match?(/\A(1|true|yes)\z/i)

    in_background { watch_restart_file }
    if @jobs
      launcher.events.after_booted { start_jobs }
      launcher.events.after_stopped { stop_jobs }
      launcher.events.before_restart { stop_jobs }
    end
  end

  private

  def app_dir = ENV["CMS_APP_DIR"].to_s.empty? ? Dir.pwd : ENV["CMS_APP_DIR"]

  def restart_file = File.join(app_dir, "tmp", "restart.txt")

  def mtime
    File.mtime(restart_file).to_f
  rescue SystemCallError
    0
  end

  def watch_restart_file
    last = mtime
    loop do
      sleep 2
      now = mtime
      next unless now > last

      last = now
      @launcher.log_writer.log "* #{restart_file} changed: restarting the workers one at a time"
      restart_jobs if @jobs
      @launcher.phased_restart
    end
  end

  # The environment the app at its directory runs with: its own bundle (a
  # release updated in place carries one) and this Ruby (config/bundled_ruby).
  def app_env
    dir = File.realpath(app_dir)
    bundle = File.join(dir, "bundle")
    {"BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
     "BUNDLE_PATH" => File.directory?(bundle) ? bundle : (ENV["CMS_IMAGE_BUNDLE_PATH"] || ENV["BUNDLE_PATH"]),
     "CMS_BUNDLED_RUBY" => ENV["CMS_BUNDLED_RUBY"] || RbConfig.ruby}
  end

  # Puma says it has booted again after a phased restart: jobs already
  # running (started again with it) stay as they are.
  def start_jobs
    return if @stopping || jobs_running?

    dir = app_dir
    @jobs_pid = Process.spawn(app_env, File.join(dir, "bin", "jobs"), chdir: dir, pgroup: true)
    @launcher.log_writer.log "* Background jobs started (pid #{@jobs_pid})"
    pid = @jobs_pid
    Thread.new do
      Process.wait(pid)
      # Gone without being asked: start again, after a pause.
      unless @stopping || pid != @jobs_pid
        sleep 5
        start_jobs
      end
    rescue Errno::ECHILD
      nil
    end
  end

  def jobs_running?
    @jobs_pid && Process.kill(0, @jobs_pid) && true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def stop_jobs
    pid = @jobs_pid or return
    @jobs_pid = nil
    Process.kill("TERM", pid)
    # Solid Queue finishes what it's running; give it the time it asks for.
    40.times { Process.kill(0, pid) && sleep(0.25) }
    Process.kill("KILL", pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def restart_jobs
    stop_jobs
    start_jobs
  end
end
