# frozen_string_literal: true

# What a site builds from, in one read (GET /api/v1/content): every live page,
# entry and global — or, given the cursor of a previous read, only what changed
# since, and what stopped being live (unpublished, trashed). A build keeps its
# store and applies the difference; Astro's content loaders do exactly that.
#
# The cursor is the time the read began, so a record changed while it ran is
# sent again next time rather than missed. A cursor older than the trash's
# retention can't account for what was purged in between, so the answer is
# then a full snapshot (`full?`), which the build replaces its store with.
class ContentSnapshot
  attr_reader :since, :now

  def self.parse_cursor(raw)
    Time.iso8601(raw.to_s) if raw.present?
  rescue ArgumentError
    nil
  end

  def initialize(since: nil, now: Time.current)
    @since = since
    @now = now
  end

  def full? = since.nil? || since < now - TrashPurgeJob::RETENTION

  def cursor = now.utc.iso8601(6)

  def pages = changed(Page.live.includes(:translation_group, :category, :tags)).order(:id).to_a

  def entries = changed(CollectionEntry.live.includes(:collection, :translation_group, :category, :tags)).order(:id).to_a

  def globals = changed(Global.all).order(:id).to_a

  # What a build must drop: records that were live and aren't now. Empty for
  # a full snapshot, which replaces everything.
  def removed
    return {pages: [], entries: [], globals: []} if full?

    {
      pages: gone(Page).map { {id: it.id, path: it.path} },
      entries: gone(CollectionEntry.includes(:collection)).map { {id: it.id, collection: it.collection&.slug, slug: it.slug} },
      globals: Global.with_discarded.where.not(deleted_at: nil).where("deleted_at > ?", since).map { {id: it.id, slug: it.slug} }
    }
  end

  private

  def changed(scope)
    full? ? scope : scope.where("updated_at > ?", since)
  end

  def gone(model)
    model.with_discarded.where("updated_at > ? OR deleted_at > ?", since, since)
      .where("deleted_at IS NOT NULL OR status <> ?", "published")
  end
end
