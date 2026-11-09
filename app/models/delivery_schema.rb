# frozen_string_literal: true

# What GET /api/v1/schema serves as its `data`: JSON Schema (2020-12) for
# each block type's data, each collection's fields, each global's data, the
# pages with fields of their own, and SEO. A site generates its types from it
# and checks every record against it.
#
# Its digest ("sha256:" of CanonicalJson of `data`) names the schema a site
# was written against: /schema carries it in meta.schema_digest and every
# /api/v1 answer in X-CMS-Schema-Digest, so a site's build can tell the
# schema moved under it (the Astro integration's cms.lock.json) and a page
# rendered on demand can tell it's out of date.
class DeliverySchema
  def self.data = new.data

  # Cached until anything the schema is made from changes.
  def self.digest
    Rails.cache.fetch(["delivery_schema_digest", *version], expires_in: 1.day) { CanonicalJson.digest(data) }
  end

  def self.version
    [BlockType, Collection, Global, Page].flat_map { [it.maximum(:updated_at)&.utc&.iso8601(6), it.count] } +
      [Setting.get(Serving::KEY).to_json]
  end

  def data
    {
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "block_types" => BlockType.order(:slug).to_h { |block_type|
        [block_type.slug, {"title" => block_type.label, "version" => block_type.version,
                           "deprecated" => block_type.deprecated, "data" => block_type.json_schema}]
      },
      "collections" => Collection.order(:slug).select { Serving.collection?(it) }.to_h { |collection|
        [collection.slug, {"title" => collection.name, "enable_blocks" => collection.enable_blocks,
                           "routable" => collection.routable, "frontmatter" => collection.frontmatter_json_schema}]
      },
      "globals" => Global.order(:slug).to_h { |global|
        [global.slug, {"title" => global.name, "data" => global.frontmatter_json_schema}]
      },
      "pages" => Page.live.order(:path).select { it.fields.any? }.to_h { |page|
        [page.path, {"title" => page.title, "frontmatter" => BlockType.json_schema_for(page.fields)}]
      },
      "seo" => BlockType.json_schema_for(SeoFields::ALL)
    }.as_json
  end
end
