# frozen_string_literal: true

# Nightly: an archive of the whole data directory, kept with the update
# backups (CMS_BACKUP_KEEP) and copied off the server by CMS_BACKUP_COMMAND
# when one is set (Cms::DataBackup#nightly). CMS_BACKUP_NIGHTLY=false turns
# it off, for an install whose host snapshots the volume instead.
class DataBackupJob < ApplicationJob
  queue_as :default

  def perform
    return if ENV["CMS_BACKUP_NIGHTLY"].to_s.strip.downcase == "false"

    Cms::DataBackup.for_install.nightly
  end
end
