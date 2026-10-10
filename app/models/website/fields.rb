# frozen_string_literal: true

# A record's field values as a theme reads them, held to the schema that
# declares them: a block's to its BlockType, an entry's frontmatter to its
# collection, a global's data to the global. A declared field reads as its
# value (nil when the record never set it); a name the schema doesn't
# declare raises, so a template written against a field that was renamed or
# never existed fails in its spec instead of rendering an empty section.
#
#   data = Website::Fields.new(block["data"], block_type.fields, name: "hero")
#   data.heading          # => "Gardens that give back"
#   data.items.first.text # repeaters and groups read the same way
#   data.headng           # => Website::Fields::Unknown: hero has no field "headng"
class Website::Fields
  class Unknown < NoMethodError; end

  # What the CMS resolved for a block (a collection list's entries, the
  # contact details), when it resolves anything.
  attr_reader :name, :resolved

  # inline_edit, row: in the editor's preview, the block's place in the
  # page, so its short text can be edited where it's drawn (Website::InlineEdit).
  def initialize(values, fields, name:, resolved: nil, inline_edit: nil, row: nil)
    @values = values.is_a?(Hash) ? values.stringify_keys : {}
    @fields = Array(fields).index_by { it["name"].to_s }
    @name = name
    @resolved = resolved
    @inline_edit = inline_edit
    @row = row
  end

  def [](key)
    key = key.to_s
    field = @fields[key] or raise Unknown.new("#{name} has no field #{key.inspect} (it has #{@fields.keys.to_sentence})", key)

    wrap(field, @values[key])
  end

  def to_h = @values

  def method_missing(method, *args)
    args.empty? && !method.end_with?("=", "?", "!") ? self[method] : super
  end

  def respond_to_missing?(method, include_private = false) = @fields.key?(method.to_s) || super

  private

  def wrap(field, value)
    case field["type"]
    when "group" then self.class.new(value, field["of"], name: "#{name}.#{field["name"]}")
    when "repeater"
      Array(value).map.with_index { |item, i| self.class.new(item, field["of"], name: "#{name}.#{field["name"]}[#{i}]") }
    when "string_list", "record_refs" then Array(value)
    when *Website::InlineEdit::EDITABLE_TYPES
      (@inline_edit && @row) ? @inline_edit.mark("blocks.#{@row}.#{field["name"]}", value) : value
    else value
    end
  end
end
