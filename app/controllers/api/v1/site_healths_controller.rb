# frozen_string_literal: true

# GET /api/v1/site_health — Site health's checks, for a build to hold the site
# to: each passes, fails, or is the site's own to judge (ok: null). The Astro
# integration reports them at build time.
class Api::V1::SiteHealthsController < Api::V1::BaseController
  requires_capability "pages:read", only: :show

  def show
    @checks = SiteHealth.checks
    @summary = SiteHealth.summary(@checks)
  end
end
