# frozen_string_literal: true

# What the delivery API sends of a record's data is what /api/v1/schema
# declares (DeliverySchema): frontmatter, block data, a global's data and
# SEO keep only their declared keys, however old the data (a field since
# removed, a key an API client stored), groups and repeater items too, as
# deep as they nest. A block of a type that no longer exists is left as it
# is. What isn't declared stays in the record, and in /api.
#
#   declared = DeliverySchema::Declared.new
#   declared.data(collection.fields, entry.frontmatter)  # => only the collection's fields
#   declared.blocks(page.expanded_blocks(live: true))    # => each block's data, its type's fields
class DeliverySchema::Declared
  def initialize(block_types = nil)
    @block_types = block_types
  end

  def data(fields, data)
    return {} unless data.is_a?(Hash)

    Array(fields).each_with_object({}) do |field, out|
      next unless field.is_a?(Hash) && data.key?(field["name"])

      out[field["name"]] = value(field, data[field["name"]])
    end
  end

  def blocks(blocks)
    return blocks unless blocks.is_a?(Array)

    blocks.map do |block|
      type = block_types[block["type"]] if block.is_a?(Hash)
      if type && block["data"].is_a?(Hash)
        block.merge("data" => data(type.fields, block["data"]))
      else
        block
      end
    end
  end

  private

  def value(field, value)
    case field["type"]
    when "group" then value.is_a?(Hash) ? data(field["of"], value) : value
    when "repeater" then value.is_a?(Array) ? value.map { it.is_a?(Hash) ? data(field["of"], it) : it } : value
    when "blocks" then blocks(value)
    else value
    end
  end

  def block_types = @block_types ||= BlockType.all.index_by(&:slug)
end
