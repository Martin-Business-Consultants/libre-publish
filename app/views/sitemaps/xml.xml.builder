# frozen_string_literal: true

absolute = ->(loc) { loc.to_s.start_with?("http://", "https://") ? loc : "#{@site_base_url}#{loc}" }

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9", "xmlns:xhtml": "http://www.w3.org/1999/xhtml") do
  @entries.each do |entry|
    xml.url do
      xml.loc absolute.(entry.loc)
      # A translated page names every language it's in, itself included (hreflang).
      if entry.alternates.present?
        ([{locale: entry.locale, loc: entry.loc}] + entry.alternates).each do |alternate|
          xml.tag! "xhtml:link", rel: "alternate", hreflang: alternate[:locale], href: absolute.(alternate[:loc])
        end
      end
      xml.lastmod    entry.lastmod if entry.lastmod
      xml.changefreq entry.changefreq if entry.changefreq
      xml.priority   format("%.2f", entry.priority) if entry.priority
    end
  end
end
