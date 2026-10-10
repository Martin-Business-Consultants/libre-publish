# frozen_string_literal: true

# A pattern: a set of blocks saved to use again (Content › Patterns). The
# block picker offers each one: an unsynced pattern goes in as a copy of
# its blocks, to change freely; a synced one goes in as a "pattern" block
# that shows the pattern's blocks as they are now, so changing the pattern
# changes every page that uses it (Page::BlockExpansion).
class BlockPattern < ApplicationRecord
  SLUG_FORMAT = Page::SLUG_FORMAT

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: {with: SLUG_FORMAT}
  validate :no_patterns_inside

  normalizes :slug, with: -> { it.to_s.strip.downcase }

  scope :ordered, -> { order(:name) }

  def to_param = slug

  # Its blocks, each with a fresh id, to insert as a copy.
  def copied_blocks = Array(blocks).map { it.merge("id" => SecureRandom.uuid) }

  private

  # A synced pattern inside a pattern could loop, and nests nothing a page
  # can't do itself.
  def no_patterns_inside
    errors.add(:blocks, "can't hold a synced pattern") if Array(blocks).any? { it.is_a?(Hash) && it["type"] == "pattern" }
  end
end
