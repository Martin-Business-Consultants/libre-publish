# frozen_string_literal: true

# A page's status (draft, published, archived) and its schedule: a
# `publish_at` or `unpublish_at` that ProcessScheduledPublishingJob acts on
# once it has passed. Changing status is an ordinary save, so the webhooks
# for the transition (Announceable) fire either way.
module Page::Publishable
  extend ActiveSupport::Concern
  include PublishesOnSchedule

  STATUSES = %w[draft published archived].freeze

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
    # Sets every page to `status`, one save at a time so each runs the same
    # callbacks as a single edit (the transition's webhook, the debounced
    # deploy). All or nothing: a page that fails validation rolls the batch
    # back and raises. Pages already at `status` are left alone, so they don't
    # announce a spurious update. The event names the pages it changed.
    def change_status_of(pages, to:)
      transaction { pages.each { |page| page.update!(status: to) unless page.status == to } }
      track_event(:bulk_status_changed, to: to, count: pages.size, paths: pages.map(&:path)) if pages.any?
      pages
    end
  end

  def published?
    status == "published"
  end

  def scheduled?
    (publish_at.present? && publish_at > Time.current && !published?) ||
      (unpublish_at.present? && unpublish_at > Time.current && published?)
  end

  # What its schedule's events name it by (PublishesOnSchedule).
  def schedule_particulars = {path: path}

  # The event for an edit saved from the admin, named for what it did to the
  # page's status (published, unpublished, or updated) the way webhooks name
  # transitions.
  def track_update(from:)
    if status == from
      track_event(:updated, path: path, status: status)
    elsif published?
      track_event(:published, path: path, from: from)
    elsif from == "published"
      track_event(:unpublished, path: path, to: status)
    else
      track_event(:updated, path: path, from: from, to: status)
    end
  end
end
