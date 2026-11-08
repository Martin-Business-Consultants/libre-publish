# frozen_string_literal: true

# Nightly: permanently deletes what has been in the trash longer than the
# retention window (Trash::RETENTION, Trash.purge_expired).
class TrashPurgeJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Trash.purge_expired(now - Trash::RETENTION)
  end
end
