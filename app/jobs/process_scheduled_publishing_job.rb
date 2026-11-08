# frozen_string_literal: true

# Runs once a minute, flipping any pages or collection entries
# whose scheduled publish/unpublish time has arrived. Status changes go
# through `update!` so existing webhooks (page.published, page.unpublished,
# entry.published, entry.unpublished) fire automatically.
#
# Idempotent: an already-published page with a past publish_at simply
# doesn't match the scope, so re-running is safe (PublishesOnSchedule).
#
# Each record goes on its own (PublishesOnSchedule.run_due): what failed is
# left due for the next run, and the job then fails naming it, so Solid
# Queue keeps a failed execution to see.
class ProcessScheduledPublishingJob < ApplicationJob
  class Incomplete < StandardError; end

  queue_as :default

  def perform(now: Time.current)
    errors = PublishesOnSchedule.run_due(now)
    raise Incomplete, "#{errors.size} scheduled change(s) left for the next run: #{errors.map(&:message).uniq.first(3).join("; ")}" if errors.any?
  end
end
