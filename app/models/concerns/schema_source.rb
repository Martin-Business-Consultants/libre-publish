# frozen_string_literal: true

# A record the delivery schema is made of (DeliverySchema): a block type, a
# collection, a global, a page (its own fields, and whether it's live), or
# Settings › General (which collections are served). Changing what the schema
# reads of one has the digest read again once writes settle, and
# `schema.changed` announced if it moved. Fan-out only.
#
#   include SchemaSource
#   schema_source_of :schema, :status, :path, :deleted_at   # only these count
module SchemaSource
  extend ActiveSupport::Concern

  included do
    # nil: any change counts.
    class_attribute :schema_source_attributes, default: nil
    class_attribute :schema_source_condition, default: nil
    after_commit :schema_may_have_changed, if: :shapes_delivery_schema?
  end

  class_methods do
    def schema_source_of(*attributes, if: nil)
      self.schema_source_attributes = attributes.map(&:to_s)
      self.schema_source_condition = binding.local_variable_get(:if)
    end
  end

  private

  def shapes_delivery_schema?
    return false if schema_source_condition && !instance_exec(&schema_source_condition)

    destroyed? || schema_source_attributes.nil? || schema_source_attributes.intersect?(saved_changes.keys)
  end

  def schema_may_have_changed
    DeliverySchema.announce_later
  end
end
