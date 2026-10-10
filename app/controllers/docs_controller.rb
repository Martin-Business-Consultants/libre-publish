# frozen_string_literal: true

# Docs: how to work with this CMS — how it works, an Astro site — and site
# health (SiteHealth), checked against the site as it is. The same are at
# /api/docs, /api/site_health and `cms docs`, `cms site-health`.
class DocsController < ApplicationController
  requires_capability "pages:read", only: [:index, :show, :site_health]

  before_action { @guides = Guide.all }

  def index
    @health = SiteHealth.summary
  end

  def show
    @guide = Guide.find(params[:slug]) or raise ActiveRecord::RecordNotFound
  end

  def site_health
    @checks = SiteHealth.checks
    @summary = SiteHealth.summary(@checks)
  end
end
