# frozen_string_literal: true

# A page's status and schedule (PublishesOnSchedule).
module Page::Publishable
  extend ActiveSupport::Concern
  include PublishesOnSchedule

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

  # What its status and schedule events name it by (PublishesOnSchedule).
  def status_particulars = {path: path}
end
