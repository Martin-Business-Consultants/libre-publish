# frozen_string_literal: true

# A page's or an entry's status (draft, published, archived) and its
# schedule, carried out by ProcessScheduledPublishingJob every minute: a passed
# `publish_at` publishes it, a passed `unpublish_at` archives it. The
# including model supplies `status_particulars`, what its status and schedule
# events name it by. Changing status is an ordinary save, so Announceable
# announces the transition either way.
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

  STATUSES = %w[draft published archived].freeze

  # Every page and entry whose time has come, published or archived. The
  # four steps run whatever happens in the others; returns the errors that
  # left something due for the next run (empty when all went).
  def self.run_due(now = Time.current)
    [
      -> { Page.publish_due(now) },
      -> { Page.unpublish_due(now) },
      -> { CollectionEntry.publish_due(now) },
      -> { CollectionEntry.unpublish_due(now) }
    ].flat_map do |step|
      step.call
    rescue StandardError => error
      Rails.error.report(error, handled: true)
      [error]
    end
  end

  included do
    # What visitors see: published, and not waiting on a schedule (the
    # scheduler flips status when publish_at or unpublish_at arrives).
    scope :live, -> { where(status: "published") }

    scope :due_to_publish, ->(now = Time.current) {
      where("publish_at IS NOT NULL AND publish_at <= ? AND status != 'published'", now)
    }
    scope :due_to_unpublish, ->(now = Time.current) {
      where("unpublish_at IS NOT NULL AND unpublish_at <= ? AND status = 'published'", now)
    }
  end

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

  def published?
    status == "published"
  end

  def scheduled?
    (publish_at.present? && publish_at > Time.current && !published?) ||
      (unpublish_at.present? && unpublish_at > Time.current && published?)
  end

  # The event for an edit, named for what it did to the status, in the audit
  # vocabulary the editors, bulk status changes and a publishing Build board
  # all speak: published when it went live, unpublished when it came down,
  # updated otherwise. `details` are the screen's own particulars (a board's
  # fields and column).
  def track_update(from:, **details)
    base = status_particulars.merge(details)
    if status == from
      track_event(:updated, **base, status: status)
    elsif published?
      track_event(:published, **base, from: from)
    elsif from == "published"
      track_event(:unpublished, **base, to: status)
    else
      track_event(:updated, **base, from: from, to: status)
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
    track_event(:schedule_failed, **status_particulars,
      scheduled: column == :publish_at ? "publish" : "unpublish",
      scheduled_for: scheduled_for&.iso8601,
      errors: error.record&.errors&.full_messages.presence || [error.message])
  end
end
