# frozen_string_literal: true

# Each URL as the Go core lists it — `loc` (absolute once the site's URL is
# set), `path`, `type` (page or entry), `locale`, `lastmod`, and `alternates`
# as {hreflang, href} — with this CMS's own keys beside them: `url` (the same
# as loc), changefreq and priority, and each alternate's `locale` and `url`.
json.data @entries do |entry|
  url = @sitemap.absolute_url(entry.loc, @site_base_url)
  json.loc url
  json.url url
  json.path entry.loc
  json.type entry.source == "page" ? "page" : "entry"
  json.extract! entry, :lastmod, :changefreq, :priority, :locale
  json.alternates(entry.alternates.map {
    href = @sitemap.absolute_url(it[:loc], @site_base_url)
    {hreflang: it[:locale], href: href, locale: it[:locale], url: href}
  })
end
json.meta({total: @entries.size, site_url: @site_base_url})
