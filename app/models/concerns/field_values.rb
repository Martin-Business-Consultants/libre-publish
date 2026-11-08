# frozen_string_literal: true

# Checking values (a page's or an entry's frontmatter, a global's data)
# against the fields that define them (FieldSchema, or an entry's
# collection), each problem an error on `attribute` led by the field's path.
module FieldValues
  extend ActiveSupport::Concern

  private

  # `whole` leads the error when the values aren't an object at all.
  def validate_field_values(attribute, values, fields:, whole: ".")
    unless values.is_a?(Hash)
      errors.add(attribute, [whole, "must be an object"].compact.join(" "))
      return
    end

    BlockType.validate_data(fields, values).each do |path, msgs|
      msgs.each { |msg| errors.add(attribute, "#{path} #{msg}") }
    end
  end
end
