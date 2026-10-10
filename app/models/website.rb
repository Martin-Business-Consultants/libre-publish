# frozen_string_literal: true

# The public website, when the CMS draws it itself. A theme (themes/*, a
# Rails engine like a plugin) registers here and ships the layout, the
# templates and the block partials; the core resolves an address to the
# record it shows (Website::Address), hands the theme its content through
# WebsiteHelper, and serves the result from Website::PagesController.
#
# Without a theme the CMS stays headless: "/" is the admin's, and a site
# built elsewhere reads the delivery API as it always has.
module Website
  # key: the theme's name (its assets live under app/assets/*/<key>);
  # views: the directory its layout and templates are in, looked in first;
  # importmap: the Importmap::Map its pages load, kept apart from the
  # admin's so a visitor never downloads the editor.
  Theme = Data.define(:key, :name, :version, :views, :importmap)

  mattr_accessor :theme

  module_function

  def register(key, name:, version:, views:, importmap: Importmap::Map.new)
    self.theme = Theme.new(key: key.to_s, name:, version:, views: views.to_s, importmap:)
  end

  def enabled? = !theme.nil?

  # Whether the theme has a template (website/emails/form, say), for a part
  # of the CMS that lets the theme draw something it otherwise draws itself.
  def draws?(template)
    enabled? && ActionView::LookupContext.new([theme.views]).exists?(template)
  end

  # The theme's template drawn outside a visit (a form email, at send time),
  # with WebsiteHelper, on the website's address; nil if the theme hasn't one.
  def render(template, **locals)
    return unless draws?(template)

    uri = URI.parse(Setting.get("general")["site_base_url"].presence || "#{Rails.configuration.x.app_protocol || "https"}://#{Site.host}")
    renderer = Website::PagesController.renderer.new(http_host: [uri.host, uri.port].join(":"), https: uri.scheme == "https")
    renderer.render(template: template, locals: locals, layout: false)
  end

  # What a cached page depends on: the content (DeliveryVersion) and the
  # theme drawing it.
  def cache_version = [theme&.key, theme&.version, DeliveryVersion.current].join("/")
end
