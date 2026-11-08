# frozen_string_literal: true

# A page's own fields: `schema` defines them (FieldSchema) and `frontmatter`
# holds their values.
module Page::Schematized
  extend ActiveSupport::Concern
  include FieldSchema

  private

  def schema_event_details = {path: path}

  # What its fields link to, stored after its blocks' (Referencing).
  def field_references = [fields, frontmatter, -1]

  def validate_frontmatter
    validate_field_values(:frontmatter, frontmatter, fields: fields)
  end
end
