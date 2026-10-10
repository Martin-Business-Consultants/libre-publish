# frozen_string_literal: true

# Daily: deletes the sessions that have ended (Session::LIFETIME,
# Session::IDLE_TIMEOUT). An ended session already signs no one in; this
# keeps the table, and Settings › Profile's session list, to the live ones.
class SessionCleanupJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    Session.expired(now).delete_all
  end
end
