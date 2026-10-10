# frozen_string_literal: true

module Cms
  # Restarts this install so it boots on changed code: a plugin installed,
  # updated or removed (PluginChange). A few seconds later, so the request or
  # job that asked has finished: it migrates (an installed plugin's tables),
  # then asks Puma to restart (its tmp_restart plugin), in a Docker container
  # as anywhere else. A plugin's stylesheets compile as it boots
  # (config/initializers/installed_plugins.rb).
  module Restart
    extend self

    # Starts the whole container again, for a release it updated to in place
    # (Upgrade::InPlace): its main process stops and Docker's restart policy
    # (Kamal's unless-stopped) starts it, so bin/docker-entrypoint picks the
    # release, backs up and migrates. Elsewhere, a Puma restart as below.
    def container_later(delay: 5)
      return later(delay:) unless ENV["CMS_RUNTIME"] == "docker"

      Thread.new do
        sleep delay
        Process.kill("TERM", 1)
      end
    end

    # The migrate and the restart run in a process of their own. What they
    # say goes to the install's log (this process's stdout, the container's
    # in Docker) and to `report`/restart.log, and how it ended to
    # `report`/exit_status, so whoever asked can tell a restart that failed
    # (a migration that broke) from one still coming (PluginChange). It starts
    # on the environment this process started with, before Bundler: that
    # keeps an image's own BUNDLE_PATH, BUNDLE_DEPLOYMENT and BUNDLE_WITHOUT
    # (the Dockerfile's), without which its bin/rails finds no gems.
    def later(delay: 5, report: Rails.root.join("log"))
      FileUtils.mkdir_p(report)
      log, status = File.join(report, "restart.log"), File.join(report, "exit_status")
      FileUtils.rm_f(status)
      script = %(sleep #{Integer(delay)}; { bin/rails db:migrate && bin/rails restart; } 2>&1 | tee "$1"; echo "${PIPESTATUS[0]}" > "$2")
      Bundler.with_original_env do
        pid = Process.spawn("/bin/bash", "-c", script, "restart", log, status,
          chdir: Rails.root.to_s, pgroup: true, in: File::NULL, out: $stdout, err: [:child, :out])
        Process.detach(pid)
      end
    end
  end
end
