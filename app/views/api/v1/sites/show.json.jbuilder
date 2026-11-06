# frozen_string_literal: true

json.data do
  json.name @general["title"].to_s
  json.description @general["description"].to_s
  json.url @general["site_base_url"].to_s
  json.default_locale @default_locale
  # Every locale but the default is a path prefix: /fr/…, /de/…
  json.locales @locales
  # The business name and how to reach it, as a contact_info block has them.
  json.contact @general.slice(*Page::BlockExpansion::CONTACT_KEYS)
  json.plugins @plugins
  # What each enabled plugin tells a build (Forms: its captcha), merged.
  json.plugin_config(Cms::Plugins.provided_all(:site_config).reduce({}, :merge))
  json.api_version "v1"
  # The widths an image's renditions are made at (variants' w<width>), ascending.
  json.image_widths Asset::Delivery::DELIVERY_WIDTHS
  # Settings › Branding: only what's set.
  json.branding Branding.current.delivered
end
# cms_url: this CMS's own address (APP_HOST), which asset URLs start with —
# a build allows it for remote images even when it reaches the API elsewhere.
json.meta({api_version: "v1", cms_version: Cms::VERSION, cms_url: root_url(**Site.url_options).chomp("/")})
