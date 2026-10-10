# frozen_string_literal: true

# The public website, when the CMS draws it itself. A theme (themes/*, a
# Rails engine like a plugin) registers here and ships the layout, the
# templates and the block partials; the core resolves an address to the
# record it shows (Website::Address), hands the theme its content through
# WebsiteHelper, and serves the result from Website::PagesController.
#
# A theme comes with the install (themes/, CMS_THEME at a Docker build) or is
# installed from Settings › Plugins like a plugin, from its GitHub release,
# into the data directory, where it outlasts updates.
#
# Without a theme the CMS stays headless: "/" is the admin's, and a site
# built elsewhere reads the delivery API as it always has.
module Website
  # key: the theme's name (its assets live under app/assets/*/<key>);
  # views: the directory its layout and templates are in, looked in first;
  # importmap: the Importmap::Map its pages load, kept apart from the
  # admin's so a visitor never downloads the editor.
  Theme = Data.define(:key, :name, :version, :views, :importmap, :design) do
    # Its design settings (Website::Design): what Settings › Themes ›
    # Customize offers.
    def settings = Array(design).map { Website::Design::Setting.from(it) }
  end

  mattr_accessor :theme
  # Every theme that registered, by key (Settings › Themes lists them).
  mattr_reader :themes, default: {}

  module_function

  # design: the settings an editor can change without touching code
  # (Website::Design), each {name:, label:, type:, default:, …}.
  def register(key, name:, version:, views:, importmap: Importmap::Map.new, design: [])
    self.theme = themes[key.to_s] = Theme.new(key: key.to_s, name:, version:, views: views.to_s, importmap:, design:)
  end

  # A theme installed from Settings › Plugins is a plugin too, and draws the
  # site only while it's switched on there.
  def enabled?
    return false if theme.nil?

    !Cms::Plugins.manifests.key?(theme.key.to_sym) || Cms::Plugins.enabled?(theme.key)
  end

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

  # What a cached page depends on: the content (DeliveryVersion), the theme
  # drawing it, and its design settings.
  def cache_version = [theme&.key, theme&.version, DeliveryVersion.current, Website::Design.version].join("/")
end
