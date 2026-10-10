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
    if blocks.is_a?(Array)
      parts.concat(blocks.filter_map { |hash|
        next unless hash.is_a?(Hash)

        block_type = BlockType.find_by(slug: hash["type"])
        next unless block_type

        block_type.searchable_text(hash["data"] || {})
      })
    end
    parts << BlockType.searchable_text_in(fields, frontmatter || {})
    parts.reject(&:blank?).join("\n\n")
  end
end
