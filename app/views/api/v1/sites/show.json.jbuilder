# frozen_string_literal: true

json.data do
  json.name @general["title"].to_s
  json.description @general["description"].to_s
  json.url @general["site_base_url"].to_s
  json.default_locale @default_locale
  # Every locale but the default is a path prefix: /fr/…, /de/…
  json.locales @locales
  json.contact @general.slice("email", "phone", "address_line1", "city", "state", "zip")
  json.plugins @plugins
  # What each enabled plugin tells a build (Forms: its captcha), merged.
  json.plugin_config(Cms::Plugins.provided_all(:site_config).reduce({}, :merge))
end
# cms_url: this CMS's own address (APP_HOST), which asset URLs start with —
# a build allows it for remote images even when it reaches the API elsewhere.
json.meta({api_version: "v1", cms_version: Cms::VERSION, cms_url: root_url(**Site.url_options).chomp("/")})
