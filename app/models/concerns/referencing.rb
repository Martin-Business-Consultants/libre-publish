# frozen_string_literal: true

# What a record links to (pages, entries, assets, collections), from its
# blocks (BlockComposed, at each block's position) and its fields, stored as
# content references so "what uses this?" is a query rather than a scan.
# Rewritten on every save.
#
# The including model says which fields and values to read, and the position
# their references are stored at (`field_references`); nil skips the rewrite.
module Referencing
  extend ActiveSupport::Concern

  included do
    has_many :content_references, as: :owner, dependent: :delete_all

    after_save :sync_references
  end

  private

  def sync_references
    fields, values, field_position = field_references
    return unless fields

    rows = []
    if respond_to?(:each_block_with_type)
      each_block_with_type do |hash, block_type, position|
        block_type.each_reference(hash["data"] || {}) { |*ref| rows << reference_row(*ref, position) }
      end
    end
    BlockType.each_reference_in(fields, values || {}) { |*ref| rows << reference_row(*ref, field_position) }

    ContentReference.transaction do
      ContentReference.where(owner: self).delete_all
      ContentReference.insert_all(rows) if rows.any?
    end
  end

  def reference_row(kind, ref_type, ref_id, position)
    {
      owner_type: self.class.polymorphic_name,
      owner_id:   id,
      ref_type:   ref_type.to_s,
      ref_id:     ref_id.to_s,
      kind:       kind.to_s,
      position:   position,
      created_at: Time.current
    }
  end
end
