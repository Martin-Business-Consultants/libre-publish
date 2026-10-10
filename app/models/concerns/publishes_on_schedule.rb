# frozen_string_literal: true

# Carrying out a page's or an entry's schedule (ProcessScheduledPublishingJob,
# every minute): a passed `publish_at` publishes it, a passed `unpublish_at`
# archives it. The including model supplies the `due_to_publish` and
# `due_to_unpublish` scopes and `schedule_particulars`, what its events name it
# by.
#
# Each record is flipped on its own, under a lock that re-reads it, so:
#
#   * two runs of the scheduler at once flip a record once (the second finds
#     it no longer due) and announce it once;
#   * one record that can't be saved doesn't hold up the others. A record
#     that fails validation would fail every minute until someone edits it,
#     so its schedule is cleared and the failure recorded
#     ("page.schedule_failed", "entry.schedule_failed": in the audit log,
#     naming the time it was scheduled for and why it didn't save), and the
#     admin stops showing it as scheduled. Anything else (the database busy)
#     leaves it due for the next run, and is returned to the job to report.
module PublishesOnSchedule
  extend ActiveSupport::Concern

  class_methods do
    # The errors that left due records for the next run (empty when all went).
    def publish_due(now = Time.current)
      each_due(due_to_publish(now)) { it.publish_on_schedule(now) }
    end

    def unpublish_due(now = Time.current)
      each_due(due_to_unpublish(now)) { it.unpublish_on_schedule(now) }
    end

    private

    def each_due(scope)
      scope.find_each.filter_map do |record|
        yield record
        nil
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: {scheduled: record.class.name, id: record.id})
        error
      end
    end
  end

  # True when this flipped it; false when it wasn't due (any longer) or
  # couldn't be saved.
  def publish_on_schedule(now = Time.current)
    on_schedule(:publish_at) do
      next false unless publish_at.present? && publish_at <= now && status != "published"

      update!(status: "published", published_at: published_at || now, publish_at: nil)
    end
  end

  def unpublish_on_schedule(now = Time.current)
    on_schedule(:unpublish_at) do
      next false unless unpublish_at.present? && unpublish_at <= now && status == "published"

      update!(status: "archived", unpublish_at: nil)
    end
  end

  private

  def on_schedule(column, &)
    with_lock(&)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => error
    give_up_schedule(column, error)
    false
  end

  # Records why, then clears the time (without callbacks or validations: the
  # record as it stands is what wouldn't save).
  def give_up_schedule(column, error)
    scheduled_for = attribute_in_database(column)
    reload
    update_columns(column => nil)
    track_event(:schedule_failed, **schedule_particulars,
      scheduled: column == :publish_at ? "publish" : "unpublish",
      scheduled_for: scheduled_for&.iso8601,
      errors: error.record&.errors&.full_messages.presence || [error.message])
  end
end
