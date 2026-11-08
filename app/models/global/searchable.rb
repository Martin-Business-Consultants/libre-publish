# frozen_string_literal: true

# A global in the admin's search index (SearchIndexed) by name, with its
# slug and description as the body; and the text of its fields, for search
# (POST /api/search).
module Global::Searchable
  extend ActiveSupport::Concern

  def search_document = {title: name, body: [slug, description].compact.join("\n")}

  def search_text
    BlockType.searchable_text_in(fields, data || {})
  end
end
