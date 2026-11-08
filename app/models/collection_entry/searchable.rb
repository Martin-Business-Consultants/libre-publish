# frozen_string_literal: true

# Entries are in the admin's search index (SearchIndexed) by title, with
# their slug, their collection's and the text of their blocks, body and
# fields as the body.
module CollectionEntry::Searchable
  extend ActiveSupport::Concern

  included do
    include SearchIndexed
  end

  def search_document = {title: title, body: [slug, collection&.slug, search_text].compact.join("\n\n")}

  def search_text
    parts = []
    each_block_with_type { |hash, block_type| parts << block_type.searchable_text(hash["data"] || {}) }
    parts << body_markdown.to_s
    parts << BlockType.searchable_text_in(collection&.fields || [], frontmatter || {})
    parts.reject(&:blank?).join("\n\n")
  end
end
