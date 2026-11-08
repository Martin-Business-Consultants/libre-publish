# frozen_string_literal: true

# A collection's schema: the frontmatter fields every entry carries
# (FieldSchema), which the manifest publishes as JSON Schema. Entry bodies
# compose via `body_markdown`; a collection can additionally opt into
# Page-style block composition by setting `enable_blocks: true`, which
# surfaces a blocks editor on each entry (e.g. templated city pages).
module Collection::Schematized
  extend ActiveSupport::Concern
  include FieldSchema

  def field(name)
    name = name.to_s
    return nil if name.empty?

    fields.find { |f| f["name"] == name }
  end

  # The yes/no fields, the ones an entries table can flip in place.
  def boolean_fields
    fields.select { |f| f.is_a?(Hash) && f["type"] == "boolean" }
  end

  def boolean_field(name)
    boolean_fields.find { |f| f["name"] == name.to_s }
  end

  # Replaces the entry shape (fields, blocks switch, notifications, Build
  # board — whatever `attributes` carries) and records it.
  def change_schema(attributes)
    update(attributes).tap { |saved| track_schema_change if saved }
  end

  def change_schema!(attributes)
    update!(attributes)
    track_schema_change
  end
end
