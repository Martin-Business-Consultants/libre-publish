# frozen_string_literal: true

# What OPTIONS on a delivery resource answers (/api/v1/pages[/<path>],
# …/collections/<slug>/entries[/<slug>], /api/v1/globals/<slug>), as the Go
# core does: the methods it takes, its parameters, and the JSON Schema of the
# answer, a record's fields as /api/v1/schema has them.
#
#   DeliverySchema::Resource.pages(list: true).as_json
#   # => {"resource" => "pages", "methods" => ["GET"], "params" => {…}, "schema" => {…}}
class DeliverySchema::Resource
  PARAMS = {
    "fields" => "Comma-separated keys to keep (id always kept); dot paths reach into objects: seo.meta_title.",
    "include" => "What to put in \"included\": assets (the default), entries, pages, or none.",
    "locale" => "Only records in this locale.",
    "page" => "The page of a list, from 1.",
    "per" => "Records a page, at most 100."
  }.freeze

  def self.pages(page: nil, list: false)
    frontmatter = page&.fields&.any? ? closed(page.fields) : {"type" => "object", "description" => "A page's own fields, when it has a schema."}
    new("pages", list, record(
      "path" => {"type" => "string"},
      "blocks" => {"type" => "array", "description" => "See /api/v1/schema for each block type."},
      "frontmatter" => frontmatter
    ))
  end

  def self.entries(collection, list: false)
    new("collections/#{collection.slug}/entries", list, record(
      "collection" => {"const" => collection.slug},
      "frontmatter" => closed(collection.fields),
      "body_markdown" => {"type" => "string", "contentMediaType" => "text/markdown"},
      "blocks" => {"type" => ["array", "null"]}
    ))
  end

  def self.global(global)
    new("globals/#{global.slug}", false, {"type" => "object", "properties" => {
      "id" => {"type" => "integer"}, "slug" => {"const" => global.slug}, "name" => {"type" => "string"},
      "data" => closed(global.fields), "updated_at" => {"type" => "string", "format" => "date-time"}
    }})
  end

  def self.record(properties)
    {"type" => "object", "properties" => {
      "id" => {"type" => "integer"}, "slug" => {"type" => "string"}, "title" => {"type" => "string"},
      "locale" => {"type" => "string"}, "url" => {"type" => "string"}, "seo" => SeoFields.json_schema,
      "published_at" => {"type" => ["string", "null"], "format" => "date-time"},
      "updated_at" => {"type" => "string", "format" => "date-time"},
      "category" => {"type" => ["object", "null"]}, "tags" => {"type" => "array"}, "translations" => {"type" => "array"}
    }.merge(properties)}
  end

  def self.closed(fields) = BlockType.json_schema_for(fields, closed: true)

  attr_reader :resource

  def initialize(resource, list, item)
    @resource = resource
    @list = list
    @item = item
  end

  def params = @list ? PARAMS : PARAMS.slice("fields", "include")

  def schema
    {"$schema" => DeliverySchema::JSON_SCHEMA, "type" => "object", "properties" => {
      "data" => @list ? {"type" => "array", "items" => @item} : @item,
      "meta" => {"type" => "object"}, "included" => {"type" => "object"}
    }}
  end
end
