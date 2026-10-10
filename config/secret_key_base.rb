# frozen_string_literal: true

require "fileutils"
require "securerandom"

# A production install's SECRET_KEY_BASE when nobody set one: made once, on
# its first boot, and kept in the data directory (CMS_DATA_DIR, as
# config/database.yml reads it) beside the database it protects, so every
# later deploy and update finds the same one, and a backup of the data
# directory restores with the key its sessions and encrypted values need.
# Sessions, signed cookies and the encryption keys
# (config/initializers/active_record_encryption.rb) all derive from it, so a
# host needn't know a Rails app wants one. Set SECRET_KEY_BASE and it wins;
# an install that already has one keeps it.
module SecretKeyBase
  module_function

  def ensure!(env = ENV, root: File.expand_path("..", __dir__))
    return if env["RAILS_ENV"] != "production" || env["SECRET_KEY_BASE"].to_s != "" || env["SECRET_KEY_BASE_DUMMY"].to_s != ""

    env["SECRET_KEY_BASE"] = read_or_make(path(env, root))
  end

  def path(env, root)
    dir = env["CMS_DATA_DIR"].to_s.empty? ? "storage" : env["CMS_DATA_DIR"]
    File.join(File.expand_path(dir, root), ".secret_key_base")
  end

  # Written whole, then linked into place, which only one process can do: two
  # booting at once agree on one key, and neither reads a half-written file.
  def read_or_make(path)
    unless File.exist?(path)
      FileUtils.mkdir_p(File.dirname(path))
      draft = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}"
      File.write(draft, SecureRandom.hex(64), perm: 0o600)
      begin
        File.link(draft, path)
      rescue Errno::EEXIST
        # Another process made it first; theirs is the key.
      ensure
        File.delete(draft)
      end
    end
    File.read(path).strip
  end
end
