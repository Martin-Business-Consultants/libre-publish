# frozen_string_literal: true

# One content change, as a rebuild or a cache purge hears of it (Deploys):
# what happened, to what, where it lives on the site, and the cache tags a
# server-rendered site tagged that content's responses with.
#
#   {"event" => "page.published", "kind" => "page", "id" => 7, "path" => "/about",
#    "locale" => "en", "tags" => ["page:about", "pages", "sitemap"]}
#
# The tags are the one vocabulary the CMS and the site share (the delivery
# API sends them in a Cache-Tag header):
#
#   page:<path>                 a page, by its path ("page:about", "page:" for the home page)
#   entry:<collection>/<slug>   an entry
#   collection:<slug>           anything listing a collection's entries
#   global:<slug>               a global (nav, footer…)
#   pages                       anything listing pages (navigation built from the tree)
#   sitemap                     the sitemap
#   redirects                   the redirect rules
#   site                        the site's name, URL and contact details (/api/v1/site)
module Deploys::Change
  module_function

  def from(event, subject)
    case subject
    when Page
      describe(event, "page", subject, path: subject.public_path, locale: subject.locale,
        tags: ["page:#{subject.path}", "pages", "sitemap"])
    when CollectionEntry
      collection = subject.collection&.slug
      describe(event, "entry", subject, path: subject.public_path, locale: subject.locale,
        tags: ["entry:#{collection}/#{subject.slug}", "collection:#{collection}", "sitemap"])
    when Global
      describe(event, "global", subject, tags: ["global:#{subject.slug}"])
    when Redirect
      describe(event, "redirect", subject, tags: ["redirects"])
    when Setting
      # Settings › General: what /api/v1/site and contact_info blocks show,
      # and the site URL the sitemap's addresses start with.
      describe(event, "settings", subject, tags: ["site", "sitemap"])
    when nil
      {"event" => event, "tags" => []}
    else
      describe(event, subject.class.name.underscore.tr("/", "_"), subject, tags: [])
    end
  end

  # The changes of a debounce window, newest last, one per record: a record
  # changed twice keeps its latest event, and every tag either asked for.
  def merge(changes)
    changes.each_with_object({}) { |change, merged|
      key = [change["kind"], change["id"] || change["event"]]
      previous = merged.delete(key)
      merged[key] = change.merge("tags" => (Array(previous&.dig("tags")) | Array(change["tags"])))
    }.values
  end

  def describe(event, kind, subject, path: nil, locale: nil, tags:)
    {"event" => event, "kind" => kind, "id" => subject.id, "path" => path, "locale" => locale, "tags" => tags}.compact
  end
end
