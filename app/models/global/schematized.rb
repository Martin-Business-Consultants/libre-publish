# frozen_string_literal: true

# A global's fields: `schema` defines them (FieldSchema) and `data` holds
# their values.
module Global::Schematized
  extend ActiveSupport::Concern
  include FieldSchema

  private

  # What its data links to (Referencing), at position 0: a global has no
  # blocks.
  def field_references = [fields, data, 0]

  def validate_data
    validate_field_values(:data, data, fields: fields, whole: nil)
  end
end
