# frozen_string_literal: true

# What an entry is made of: frontmatter in its collection's fields, and blocks
# when the collection has opted into them (`enable_blocks`). Its blocks check
# exactly as a page's do (BlockComposed).
module CollectionEntry::Composed
  extend ActiveSupport::Concern
  include BlockComposed
  include FieldValues

  # Whether this entry's collection has opted into the page-style block
  # composer. Entries in non-block collections must keep `blocks` empty.
  def enable_blocks?
    collection&.enable_blocks?
  end

  private

  def validate_frontmatter
    return unless collection

    validate_field_values(:frontmatter, frontmatter, fields: collection.fields)
  end

  # What its frontmatter links to, after its blocks' (Referencing); nothing
  # is rewritten without a collection to read the fields from.
  def field_references = collection && [collection.fields, frontmatter, -1]

  # The shape check is cheap and always runs; per-block validation only runs
  # once the collection has opted in.
  def validates_each_block? = enable_blocks?

  # A collection must set `enable_blocks` before its entries can carry blocks.
  # Otherwise stray block data would render nowhere and bypass the per-block
  # validation an editor expects.
  def validate_blocks_enabled
    return if enable_blocks?

    errors.add(:blocks, "are not enabled for this collection") if blocks.present?
  end
end
