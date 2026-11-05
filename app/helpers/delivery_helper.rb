# frozen_string_literal: true

# For the delivery API's views (app/views/api/v1): a record's data as
# delivered, only what /api/v1/schema declares (DeliverySchema::Declared),
# with block types looked up once per answer.
module DeliveryHelper
  def delivered = @delivered ||= DeliverySchema::Declared.new

  # Blocks as a site renders them: patterns expanded, what they pull in
  # resolved (live content only), each one's data its type's fields.
  def delivered_blocks(blocks) = delivered.blocks(Page::BlockExpansion.new(blocks, live: true).blocks)
end
