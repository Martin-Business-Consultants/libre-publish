# frozen_string_literal: true

# Search across pages and collection entries for the API (POST /api/search,
# cms search): the admin's search index (SearchIndexed), 25 of each, best
# match first, each with a highlighted snippet of where it matched.
#
# Only what the caller may read: no pages without pages:read, no entries
# without entries:read, and only live ones for a caller who can't write
# them — the site's own token never sees a draft's title or text.
class Search
  LIMIT = 25
  SNIPPET = {body: {markers: ["<mark>", "</mark>"], snippet: {words: 12}}}.freeze

  # `can` answers whether the caller holds a capability ("pages:write").
  def initialize(query, can:)
    @query = query
    @can = can
  end

  def pages
    return [] unless @can.call("pages:read")

    hits(Page, among: @can.call("pages:write") ? Page.all : Page.live) do |page|
      {id: page.id, slug: page.slug, title: page.title, status: page.status, locale: page.locale, updated_at: page.updated_at}
    end
  end

  def entries
    return [] unless @can.call("entries:read")

    hits(CollectionEntry, among: @can.call("entries:write") ? CollectionEntry.all : CollectionEntry.live) do |entry|
      {id: entry.id, slug: entry.slug, collection_slug: entry.collection.slug, title: entry.title, status: entry.status,
       locale: entry.locale, updated_at: entry.updated_at}
    end
  end

  private

  # The best matches among `among`: the records that hold the term narrowed
  # to those in SQL first, so drafts left out don't use up the LIMIT.
  def hits(model, among:)
    ids = among.where(id: model.search_index_ids(@query)).ids
    return [] if ids.empty?

    model.search(@query).filter(record_id: ids).highlight(**SNIPPET).limit(LIMIT).results.map do |record|
      yield(record).merge(snippet: record.hit.highlight(:body))
    end
  end
end
