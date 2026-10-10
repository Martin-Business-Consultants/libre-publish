# frozen_string_literal: true

# Where a content record lives on the published site.
#
# Three things need to agree on this and used to compute it separately: the
# sitemap, the delivery API and the content webhooks. They must agree, because
# a webhook's receiver matches records *by URL* (search and analytics rows come
# keyed by address) — a webhook that announces a different URL than the
# sitemap published is a record the receiver can never match. See
# docs/webhooks.md.
#
# The including class provides `default_public_path`, without a locale; a
# record in any locale but the site's default (Settings › General) is then
# served under that locale's prefix — "/fr/a-propos" — and the page at path
# "home" is the site's root, "/" (or "/fr"). An SEO canonical overrides all
# of it, since a canonical is by definition the address we want to be known by.
# The admin SEO panel saves it as `seo["canonical_url"]`; `seo["canonical"]` is
# still read as a fallback for records written before that key settled.
module PubliclyAddressable
  extend ActiveSupport::Concern

  # Site-relative, with a leading slash: "/about", "/blog/hello".
  def public_path
    seo_canonical.presence || localized(default_public_path)
  end

  # Absolute, using the site's configured public origin. Falls back to the
  # relative path when no origin is set rather than inventing one — a wrong
  # absolute URL is worse than an honest relative one, because the consumer
  # can't tell it's wrong.
  def public_url
    path = public_path
    return path if path.to_s.start_with?("http://", "https://")

    base = self.class.site_base_url
    return path if base.blank?

    "#{base.chomp("/")}#{path}"
  end

  private

  def localized(path)
    path = "/" if path == "/home"
    prefix = locale.to_s if respond_to?(:locale) && locale.present? && locale.to_s != self.class.default_locale
    return path unless prefix && !path.match?(%r{\A/#{Regexp.escape(prefix)}(/|\z)})

    path == "/" ? "/#{prefix}" : "/#{prefix}#{path}"
  end

  def seo_canonical
    seo_hash["canonical_url"].to_s.strip.presence || seo_hash["canonical"].to_s.strip
  end

  def seo_hash
    respond_to?(:seo) && seo.is_a?(Hash) ? seo : {}
  end

  class_methods do
    def site_base_url
      Setting.get("general")["site_base_url"].to_s.strip
    end

    def default_locale
      Setting.get("general")["default_locale"].presence || "en"
    end
  end
end
