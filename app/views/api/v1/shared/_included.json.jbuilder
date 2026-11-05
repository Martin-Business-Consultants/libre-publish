# frozen_string_literal: true

# What the records point at (Api::DeliveryShaping, ?include=): every asset,
# resolved, when there's a media library (the default), and, when asked for,
# the live entries ({"<collection>/<slug>" => entry}) and pages ({path =>
# page}) they link to, as far as they're served.
records = local_assigns.fetch(:records, [])
entries, pages = included?(:entries) || included?(:pages) ? ContentReference.live_referenced_by(records) : [[], []]
entries = entries.select { Serving.collection?(it.collection) }
pages = [] unless Serving.pages?

if assets || included?(:entries) || included?(:pages)
  json.included do
    json.assets assets if assets
    if included?(:entries)
      json.entries do
        entries.each { |entry| json.set!("#{entry.collection.slug}/#{entry.slug}") { json.partial! "api/v1/entries/entry", entry: entry } }
      end
    end
    if included?(:pages)
      json.pages do
        pages.each { |page| json.set!(page.path) { json.partial! "api/v1/pages/page", page: page } }
      end
    end
  end
end
