# frozen_string_literal: true

# Editing in the editor's preview: each value that can be edited in place —
# the title, and the short text of the page's own blocks (string and
# plain-text fields) — is drawn with invisible markers around it naming
# where it comes from, whatever the theme does with it. The preview's script
# (inline_edit.js) turns marked text into editable text and strips the
# markers from attributes and the <head>; an edit goes back to the editor's
# form field (website_preview_controller), and saving saves the form.
#
# A marker is U+2063, the field's number in four zero-width characters, U+2063;
# the value; then U+2064.
class Website::InlineEdit
  EDITABLE_TYPES = %w[string plain_text].freeze
  START = "⁣"
  FINISH = "⁤"
  DIGITS = ["​", "‌", "‍", "⁠"].freeze

  attr_reader :fields

  def initialize
    @fields = []
  end

  # A value, marked as the field at `path` ("title", "blocks.2.heading").
  def mark(path, value)
    return value unless value.is_a?(String) && value.present? && !value.include?(START)

    @fields << path
    "#{START}#{encode(@fields.size - 1)}#{START}#{value}#{FINISH}"
  end

  def encode(number) = number.to_s(4).chars.map { DIGITS[it.to_i] }.join

  # The script and its field list, for the end of the preview's <body>.
  def tags(view)
    view.safe_join([
      view.tag.script(ERB::Util.json_escape({fields: @fields}.to_json).html_safe, type: "application/json", id: "lp-inline-edit"), # rubocop:disable Rails/OutputSafety
      view.javascript_include_tag("inline_edit", defer: true)
    ])
  end
end
