# frozen_string_literal: true

# A record whose `schema` defines fields in BlockType's field DSL (every type
# but `blocks`): a page's own fields, a collection's entry frontmatter, a
# global's data. The including model names what its schema events carry
# (`schema_event_details`, the slug by default).
#
#   page.fields                  # => [{"name" => "summary", "type" => "text"}, …]
#   page.update_schema(fields)   # replaces the definitions and records page.schema_updated
module FieldSchema
  extend ActiveSupport::Concern
  include FieldValues

  FIELD_TYPES = BlockType::COLLECTION_FIELD_TYPES

  def fields
    return [] unless schema.is_a?(Hash)

    schema["fields"] || []
  end

  # The fields as JSON Schema, for the manifest and the delivery API.
  def frontmatter_json_schema
    BlockType.json_schema_for(fields)
  end

  # Replaces the field definitions (not their values); the whole list is sent
  # every time.
  def update_schema(fields)
    update(schema: {"fields" => fields}).tap { |saved| track_schema_change if saved }
  end

  def update_schema!(fields)
    update_schema(fields) || raise(ActiveRecord::RecordInvalid, self)
  end

  private

  def schema_event_details = {slug: slug}

  def track_schema_change
    track_event(:schema_updated, **schema_event_details)
  end

  def validate_schema_shape
    unless schema.is_a?(Hash)
      errors.add(:schema, "must be an object")
      return
    end

    raw_fields = schema["fields"]
    if raw_fields && !raw_fields.is_a?(Array)
      errors.add(:schema, "fields must be an array")
      return
    end

    BlockType.validate_fields_definition(raw_fields || [], allowed_types: FIELD_TYPES)
      .each { |msg| errors.add(:schema, msg) }
  end
end
