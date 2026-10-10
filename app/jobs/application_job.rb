# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # The database was busy: SQLite's "database is locked" past the busy
  # timeout (Active Record raises StatementTimeout for it), or no connection
  # free in the pool. Nothing was committed, and the next attempt usually
  # gets through. After the last, the job fails and Solid Queue keeps it.
  retry_on ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked, ActiveRecord::ConnectionTimeoutError,
    wait: :polynomially_longer, attempts: 5

  # The record the job was for is gone (deleted before the job ran): there's
  # nothing left to do.
  discard_on ActiveJob::DeserializationError
end
