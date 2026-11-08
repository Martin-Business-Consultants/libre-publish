# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # A job queued inside a transaction waits for it to commit, so it never
  # runs ahead of the rows it reads, and isn't queued at all if they roll
  # back. The queue is another SQLite file, outside the transaction.
  self.enqueue_after_transaction_commit = true

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
