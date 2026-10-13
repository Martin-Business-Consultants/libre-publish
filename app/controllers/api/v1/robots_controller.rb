# frozen_string_literal: true

# GET /api/v1/robots — the site's robots.txt for a frontend to publish (as
# written on the Sitemap screen, or made from Settings › Search), with the
# sitemap's address on the site; /api/v1/robots.txt — the file itself.
class Api::V1::RobotsController < Api::V1::BaseController
  requires_capability "pages:read", only: :show

  def show
    base_url = Setting.get("general")["site_base_url"].to_s
    @robots = Website::Robots.new(base_url, frontend: true)
    cache_tags("robots")
    respond_to do |format|
      format.json
      format.text { render plain: @robots.to_s }
    end
  end
end
