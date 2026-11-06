# frozen_string_literal: true

# The SEO panel of a page's or entry's form, as schema fields, so the content
# form renders and reads it like any other object. Keys the panel doesn't
# show (twitter_title, canonical, anything an API client stored) are carried
# over untouched by ContentForm.
module SeoFields
  OG_TYPES = [
    ["Article", "article"], ["Product", "product"], ["Profile", "profile"],
    ["Video", "video.other"], ["Website", "website"]
  ].freeze

  TWITTER_CARDS = [
    ["App", "app"], ["Player", "player"], ["Summary", "summary"],
    ["Summary, large image", "summary_large_image"]
  ].freeze

  SCHEMA_TYPES = [
    ["Article", "Article"], ["Blog posting", "BlogPosting"], ["Event", "Event"],
    ["FAQ page", "FAQPage"], ["How-to", "HowTo"], ["Local business", "LocalBusiness"],
    ["News article", "NewsArticle"], ["Product", "Product"], ["Recipe", "Recipe"],
    ["WebPage (default)", "WebPage"]
  ].freeze

  SEARCH = [
    {"name" => "meta_title", "label" => "Meta title", "type" => "string",
     "help" => "Shown as the result's title. Defaults to the page title."},
    {"name" => "meta_description", "label" => "Meta description", "type" => "plain_text",
     "help" => "A concise summary that search engines and previews show under the title."},
    {"name" => "canonical_url", "label" => "Canonical URL", "type" => "url"},
    {"name" => "focus_keyword", "label" => "Focus keyword", "type" => "string"},
    {"name" => "noindex", "label" => "Hide from search engines", "type" => "boolean"},
    {"name" => "nofollow", "label" => "Ask search engines not to follow links", "type" => "boolean"},
    {"name" => "exclude_from_sitemap", "label" => "Leave out of the sitemap", "type" => "boolean",
     "help" => "Search engines can still find it through links; to hide it from them too, use the switch above."}
  ].freeze

  SOCIAL = [
    {"name" => "og_image_id", "label" => "Social share image", "type" => "asset"},
    {"name" => "og_title", "label" => "Title override", "type" => "string"},
    {"name" => "og_description", "label" => "Description override", "type" => "plain_text"},
    {"name" => "og_type", "label" => "Open Graph type", "type" => "select", "choices" => OG_TYPES},
    {"name" => "twitter_card", "label" => "Twitter card", "type" => "select", "choices" => TWITTER_CARDS}
  ].freeze

  STRUCTURED = [
    {"name" => "schema_type", "label" => "schema.org type", "type" => "select", "choices" => SCHEMA_TYPES},
    {"name" => "json_ld", "label" => "JSON-LD", "type" => "json",
     "help" => "One node or a list of nodes, each with an @type. Leave blank to use the schema.org type above."}
  ].freeze

  ALL = (SEARCH + SOCIAL + STRUCTURED).freeze

  # What the delivery API sends of a record's `seo`, and its JSON Schema
  # (/api/v1/schema's `seo`): the panel's fields, as the Go core declares
  # them, and the keys this CMS keeps there besides — the sitemap's priority
  # and change frequency (the Sitemap screen), a Twitter image, and the
  # `canonical` older records hold (deprecated: read canonical_url, which a
  # record with only `canonical` is delivered with too). Anything else stored
  # in `seo` stays in the record and in /api, but isn't delivered.
  DELIVERED = [
    *ALL.map { it.slice("name", "label").merge("type" => {"plain_text" => "text", "select" => "string", "json" => "json"}.fetch(it["type"], it["type"])) },
    {"name" => "twitter_image_id", "label" => "Twitter image", "type" => "asset"},
    {"name" => "canonical", "label" => "Canonical URL (deprecated: canonical_url)", "type" => "url"}
  ].freeze

  def self.json_schema = @json_schema ||= build_json_schema.freeze

  def self.build_json_schema
    schema = BlockType.json_schema_for(DELIVERED.reject { it["type"] == "json" }, closed: true)
    schema["properties"]["sitemap_priority"] = {"title" => "Sitemap priority", "x-cms-type" => "number", "type" => "number", "minimum" => 0, "maximum" => 1}
    schema["properties"]["sitemap_changefreq"] = {"title" => "Sitemap change frequency", "x-cms-type" => "select", "type" => "string", "enum" => Sitemap::CHANGEFREQS}
    # JSON-LD isn't a field type: one node or a list of them, each an object.
    schema["properties"]["json_ld"] = {"x-cms-type" => "json", "title" => "JSON-LD", "description" => "One node or a list of nodes, each with an @type.",
                                       "oneOf" => [{"type" => "object"}, {"type" => "array", "items" => {"type" => "object"}}]}
    schema
  end

  # A record's `seo` as delivered: only what json_schema declares, with an
  # older record's `canonical` given as canonical_url too.
  def self.delivered(seo)
    seo = seo.is_a?(Hash) ? seo.stringify_keys : {}
    seo = seo.merge("canonical_url" => seo["canonical"]) if seo["canonical_url"].to_s.strip.empty? && seo["canonical"].to_s.strip.present?
    seo.slice(*json_schema["properties"].keys)
  end
end
