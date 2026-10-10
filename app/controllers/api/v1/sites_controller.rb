# frozen_string_literal: true

# GET /api/v1/site — the site as a build configures itself from it: its name
# and public URL, its locales (path prefixes, the default unprefixed), the
# API version, and what plugins add (a form's spam protection, say) under
# `plugin_config` (Cms::Plugins.provided_all(:site_config)).
class Api::V1::SitesController < Api::V1::BaseController
  requires_capability "pages:read", only: :show

  def show
    @general = Setting.get("general")
    @default_locale = @general["default_locale"].presence || "en"
    @locales = ([@default_locale] + Page.live.distinct.pluck(:locale) + CollectionEntry.live.distinct.pluck(:locale)).compact_blank.uniq
    @plugins = Cms::Plugins.manifests.keys.select { Cms::Plugins.enabled?(it) }
    cache_tags("site")
  end
end
