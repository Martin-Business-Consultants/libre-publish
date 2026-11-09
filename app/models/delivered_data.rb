# frozen_string_literal: true

# What the delivery API hands a site of a record's field data: only the keys
# its schema declares (DeliverySchema), at every depth -- block data, nested
# blocks, groups, repeater items, links, frontmatter, global data and SEO.
#
# The schema closes every object it describes (additionalProperties: false),
# and a site may hold content to it strictly (the Astro integration does).
# Data keeps whatever was written to it -- a field renamed or removed from a
# block type leaves its old key behind in every block that had it -- so this
# is where the schema's promise is kept: a key the schema doesn't name is
# never delivered. A block whose type no longer exists isn't either; there's
# no schema to say what it holds, and so nothing a site could render it with.
class DeliveredData
  LINK_KEYS = %w[kind value collection].freeze
  NESTED_BLOCK_KEYS = %w[id type version data].freeze

  def initialize
    @block_types = {}
    @collections = {}
  end

  # Field data, as declared by `fields` (the field DSL).
  def fields(field_defs, data)
    return data unless data.is_a?(Hash)

    field_defs = Array(field_defs)
    field_defs.each_with_object({}) do |fd, out|
      name = fd["name"]
      next unless data.key?(name)

      out[name] = value(fd, data[name])
    end
  end

  # Top-level blocks, as a page or entry delivers them: id, type and version
  # as they are, `data` filtered, and a collection list's resolved entries
  # filtered as their collection declares (Page::BlockExpansion).
  def blocks(blocks)
    Array(blocks).filter_map do |block|
      block = block.to_h.stringify_keys
      block_type = block_type(block["type"])
      next unless block_type

      block = block.merge("data" => fields(block_type.fields, block["data"] || {}))
      block["resolved"] = resolved(block["resolved"]) if block["resolved"].is_a?(Hash)
      block
    end
  end

  # An entry's frontmatter, blocks and SEO, as its collection declares.
  def entry(entry_hash)
    collection = collection(entry_hash["collection"])
    entry_hash.merge(
      "frontmatter" => fields(collection&.fields, entry_hash["frontmatter"] || {}),
      "blocks" => blocks(entry_hash["blocks"]),
      "seo" => fields(SeoFields::ALL, entry_hash["seo"] || {})
    ).slice(*entry_hash.keys)
  end

  private

  def value(fd, val)
    case fd["type"]
    when "group" then fields(fd["of"], val)
    when "repeater" then val.is_a?(Array) ? val.map { |item| fields(fd["of"], item) } : val
    when "link" then val.is_a?(Hash) ? val.slice(*LINK_KEYS) : val
    when "blocks" then val.is_a?(Array) ? nested_blocks(val) : val
    else val
    end
  end

  def nested_blocks(items)
    items.filter_map do |item|
      next item unless item.is_a?(Hash)

      block_type = block_type(item["type"])
      next unless block_type

      item.slice(*NESTED_BLOCK_KEYS).merge("data" => fields(block_type.fields, item["data"] || {}))
    end
  end

  def resolved(resolved)
    return resolved unless resolved["entries"].is_a?(Array)

    resolved.merge("entries" => resolved["entries"].map { it.is_a?(Hash) ? entry(it.stringify_keys) : it })
  end

  def collection(slug)
    return if slug.blank?

    @collections.fetch(slug) { @collections[slug] = Collection.find_by(slug: slug) }
  end

  def block_type(slug)
    return if slug.blank?

    @block_types.fetch(slug) { @block_types[slug] = BlockType.find_by(slug: slug) }
  end
end
