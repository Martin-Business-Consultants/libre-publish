# frozen_string_literal: true

# Nightly: permanently deletes what has been in the trash longer than the
# retention window (Trash.purge_expired).
class TrashPurgeJob < ApplicationJob
  RETENTION = 30.days

  queue_as :default

  def perform(now: Time.current)
    Trash.purge_expired(now - RETENTION)
  end
end
