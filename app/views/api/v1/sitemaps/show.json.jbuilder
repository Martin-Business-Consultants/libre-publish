# frozen_string_literal: true

json.data @entries do |entry|
  json.url @sitemap.absolute_url(entry.loc, @site_base_url)
  json.path entry.loc
  json.extract! entry, :lastmod, :changefreq, :priority, :locale
  json.alternates(entry.alternates.map { {locale: it[:locale], url: @sitemap.absolute_url(it[:loc], @site_base_url)} })
end
json.meta({total: @entries.size, site_url: @site_base_url})
