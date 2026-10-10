# frozen_string_literal: true

# Developers: how frontends work with this headless CMS. It keeps content and
# serves it as JSON; a site (the Astro app) fetches and renders it. The screen
# says so, lists the delivery API a site reads (/api/v1), walks through
# connecting an Astro site with the @librepublish/astro packages, and shows the
# frontend this CMS serves and what its build last reported (Frontend).
class DevelopersController < ApplicationController
  requires_capability "pages:read", only: :show

  # The delivery API (docs/delivery-api.md): live content only, one shape.
  ENDPOINTS = [
    ["GET", "/api/v1/site", "The site: its URL, locales, and what plugins add (a form's captcha)"],
    ["GET", "/api/v1/content", "Every live page, entry and global; ?since=<cursor> for what changed"],
    ["GET", "/api/v1/pages/:path", "One page: blocks expanded, fields, SEO, translations, its assets"],
    ["GET", "/api/v1/collections/:slug/entries", "A collection's live entries (and /:slug for one)"],
    ["GET", "/api/v1/globals/:slug", "A global: navigation, footer, contact details"],
    ["GET", "/api/v1/schema", "JSON Schema for block types, collections, globals and SEO"],
    ["GET", "/api/v1/sitemap", "The URLs the site's sitemap.xml lists, with hreflang"],
    ["GET", "/api/v1/redirects.txt", "The redirect rules as a Cloudflare _redirects file"],
    ["GET", "/api/v1/site_health", "Site health's checks, for the build to hold the site to"]
  ].freeze

  def show
    @build = Frontend.last_build
    @plugin_endpoints = Cms::Plugins.manifest_listing.flat_map { |plugin| plugin[:endpoints].map { [plugin[:name], it] } }
    @service_tokens = ServiceToken.active.count
    @webhooks = Webhook.count
    @deploys = Deploys.ready?
    @counts = {pages: Page.count, collections: Collection.count, entries: CollectionEntry.count, globals: Global.count, block_types: BlockType.count}
  end
end
