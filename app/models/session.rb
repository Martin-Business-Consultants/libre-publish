# frozen_string_literal: true

# A signed-in browser. It lasts LIFETIME from sign-in, and ends sooner when
# it goes unused for IDLE_TIMEOUT. An ended session no longer signs anyone
# in, and SessionCleanupJob deletes it.
class Session < ApplicationRecord
  LIFETIME = 30.days
  IDLE_TIMEOUT = 14.days
  # How often a request records that the session is in use: once an hour
  # rather than a write per request.
  SEEN_EVERY = 1.hour

  belongs_to :user

  scope :expired, ->(now = Time.current) {
    where(created_at: ...now - LIFETIME).or(where(last_seen_at: ...now - IDLE_TIMEOUT))
  }

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
    self.last_seen_at = Time.current
  end

  def expires_at = created_at + LIFETIME

  def expired?(now = Time.current)
    created_at <= now - LIFETIME || (last_seen_at || created_at) <= now - IDLE_TIMEOUT
  end

  # Records that the session is in use, at most once per SEEN_EVERY.
  def seen!(now = Time.current)
    update_column(:last_seen_at, now) if last_seen_at.nil? || last_seen_at <= now - SEEN_EVERY
  end
end
