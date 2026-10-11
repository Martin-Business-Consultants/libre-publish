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
#
# An image (an asset field of a block) can't carry markers: its value is an
# id the theme turns into a URL. Instead each block's image fields are noted
# by row (image), and the <img> website_image_tag draws for one while that
# block renders names its field (data-lp-image), for the preview's Replace
# and Edit.
class Website::InlineEdit
  EDITABLE_TYPES = %w[string plain_text].freeze
  START = "⁣"
  FINISH = "⁤"
  DIGITS = ["​", "‌", "‍", "⁠"].freeze

  attr_reader :fields

  def initialize
    @fields = []
    @images = Hash.new { |hash, row| hash[row] = {} }
  end

  # A block's image field: row, its name, the asset id it holds.
  def image(row, name, id)
    @images[row][id.to_s] ||= "blocks.#{row}.#{name}" if id.present?
  end

  # The field an image drawn in that block's row comes from, if it's one.
  def image_field(row, id) = @images.fetch(row, {})[id.to_s]

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
