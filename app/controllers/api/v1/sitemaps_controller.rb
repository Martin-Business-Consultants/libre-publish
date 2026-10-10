# frozen_string_literal: true

# GET /api/v1/sitemap — the URLs a site's sitemap.xml lists, absolute on the
# public site, with lastmod and their translations (hreflang alternates).
class Api::V1::SitemapsController < Api::V1::BaseController
  requires_capability "pages:read", only: :show

  def show
    @sitemap = Sitemap.new
    @site_base_url = Setting.get("general")["site_base_url"].to_s
    @entries = @sitemap.entries.select(&:included?)
    cache_tags("sitemap")
  end
end
