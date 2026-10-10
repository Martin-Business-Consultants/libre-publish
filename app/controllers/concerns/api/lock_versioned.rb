# frozen_string_literal: true

# Optimistic locking for the API's writes to pages, entries and globals.
# Reading one answers with the version it's at, in a header (the JSON is a
# frozen contract, so it isn't in the body):
#
#   GET /api/pages/about                 →  X-Lock-Version: 4
#
# and a write that sends it back is refused if someone saved in between:
#
#   PATCH /api/pages/about {"page": {"title": "…", "lock_version": 4}}
#                                        →  409 {"error": "conflict", "lock_version": 5}
#
# A write that doesn't send one is applied as it always was: the CLI, MCP and
# scripts keep working unchanged, and opt in by sending what they read.
module Api::LockVersioned
  extend ActiveSupport::Concern

  class InvalidLockVersion < StandardError; end

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :render_stale_write
    rescue_from InvalidLockVersion, with: :render_invalid_lock_version
  end

  class_methods do
    # Says the record's version on show, create and update, from the
    # instance variable the controller loads it into.
    def advertises_lock_version(ivar)
      after_action(only: %i[show create update]) do
        record = instance_variable_get(ivar)
        response.set_header("X-Lock-Version", record.lock_version.to_s) if record&.persisted?
      end
    end
  end

  private

  # Before the save: the version the client read, if it sent one.
  def expect_lock_version(record, scope)
    value = params.dig(scope, :lock_version)
    return if value.nil?
    raise InvalidLockVersion unless value.to_s.match?(/\A\d+\z/)

    record.lock_version = value.to_i
  end

  def render_stale_write(error)
    current = error.record.class.unscoped.where(id: error.record.id).pick(:lock_version)
    render json: {error: "conflict", message: "Someone saved it since the lock_version you sent: read it again and reapply your change",
                  lock_version: current}, status: :conflict
  end

  def render_invalid_lock_version
    render json: {error: "invalid", message: "lock_version must be a whole number"}, status: :unprocessable_content
  end
end
