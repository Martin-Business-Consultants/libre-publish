# frozen_string_literal: true

# Runs once a minute, flipping any pages or collection entries
# whose scheduled publish/unpublish time has arrived. Status changes go
# through `update!` so existing webhooks (page.published, page.unpublished,
# entry.published, entry.unpublished) fire automatically.
#
# Idempotent: an already-published page with a past publish_at simply
# doesn't match the scope, so re-running is safe (PublishesOnSchedule).
#
# The four steps run whatever happens in the others, and each record on its
# own: what failed is left due for the next run, and the job then fails
# naming it, so Solid Queue keeps a failed execution to see.
class ProcessScheduledPublishingJob < ApplicationJob
  class Incomplete < StandardError; end

  queue_as :default

  def perform(now: Time.current)
    errors = [
      -> { Page.publish_due(now) },
      -> { Page.unpublish_due(now) },
      -> { CollectionEntry.publish_due(now) },
      -> { CollectionEntry.unpublish_due(now) }
    ].flat_map { run(it) }

    raise Incomplete, "#{errors.size} scheduled change(s) left for the next run: #{errors.map(&:message).uniq.first(3).join("; ")}" if errors.any?
  end

  private

  def run(step)
    step.call
  rescue StandardError => error
    Rails.error.report(error, handled: true)
    [error]
  end
end
