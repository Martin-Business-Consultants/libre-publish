# frozen_string_literal: true

# An entry's status and schedule, as for pages (PublishesOnSchedule).
module CollectionEntry::Publishable
  extend ActiveSupport::Concern
  include PublishesOnSchedule

  class_methods do
    # Sets every entry of `collection` to `to`, all or nothing, and records one
    # event naming them. One save per entry (not update_all) so each fires the
    # webhook and debounced deploy a single edit does.
    def change_status_of(entries, to:, collection:)
      transaction { entries.each { |entry| entry.update!(status: to) unless entry.status == to } }
      track_event(:bulk_status_changed, collection: collection.slug, to: to, count: entries.size, slugs: entries.map(&:slug)) if entries.any?
      entries
    end
  end

  # What its status and schedule events name it by (PublishesOnSchedule).
  def status_particulars = {collection: collection&.slug, slug: slug}

  def track_creation
    track_event(:created, collection: collection.slug, slug: slug, status: status)
  end
end
