# frozen_string_literal: true

# Pages are in the admin's search index (SearchIndexed) by title, with their
# path and the text of their blocks and fields as the body.
module Page::Searchable
  extend ActiveSupport::Concern

  included do
    include SearchIndexed
  end

  def search_document = {title: title, body: [path, search_text].compact.join("\n\n")}

  def search_text
    parts = []
    each_block_with_type { |hash, block_type| parts << block_type.searchable_text(hash["data"] || {}) }
    parts << BlockType.searchable_text_in(fields, frontmatter || {})
    parts.reject(&:blank?).join("\n\n")
  end
end
