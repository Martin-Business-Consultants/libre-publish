# frozen_string_literal: true

# A body of blocks (a page's, or an entry's when its collection allows them),
# each `{id, type, version, data}` checked against its block type's fields.
# The including model can hold the per-block check back
# (`validates_each_block?`): an entry does until its collection opts in.
module BlockComposed
  extend ActiveSupport::Concern

  # Each well-formed block with its BlockType and its position, skipping
  # anything that isn't a hash or names no known type.
  def each_block_with_type
    Array(blocks).each_with_index do |hash, position|
      next unless hash.is_a?(Hash)

      block_type = BlockType.find_by(slug: hash["type"])
      yield hash, block_type, position if block_type
    end
  end

  private

  def validates_each_block? = true

  def validate_blocks_shape
    errors.add(:blocks, "must be an array") unless blocks.is_a?(Array)
  end

  def validate_each_block
    return unless validates_each_block? && blocks.is_a?(Array)

    blocks.each_with_index do |hash, i|
      unless hash.is_a?(Hash)
        errors.add(:blocks, "blocks[#{i}] must be an object")
        next
      end

      slug = hash["type"]
      unless slug.is_a?(String)
        errors.add(:blocks, "blocks[#{i}].type must be a string")
        next
      end

      block_type = BlockType.find_by(slug: slug)
      unless block_type
        errors.add(:blocks, "blocks[#{i}]: unknown type '#{slug}'")
        next
      end

      block_type.validate_data(hash["data"] || {}).each do |path, msgs|
        field_part = path.empty? ? "" : ".#{path}"
        msgs.each { |msg| errors.add(:blocks, "blocks[#{i}].data#{field_part} #{msg}") }
      end
    end
  end
end
