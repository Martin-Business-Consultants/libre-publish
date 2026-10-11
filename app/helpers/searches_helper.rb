# frozen_string_literal: true

module SearchesHelper
  # Where a search result opens: the record's own edit screen, or for a
  # collection, its entries.
  def search_result_path(record)
    case record
    when Page then edit_page_path(record.path)
    when CollectionEntry then edit_collection_entry_path(record.collection.slug, record.slug)
    when Collection then collection_entries_path(record.slug)
    when Global then edit_global_path(record.slug)
    when BlockType then edit_block_type_path(record.slug)
    when Redirect then edit_tools_redirect_path(record)
    when User then edit_user_path(record)
    when Role then edit_role_path(record)
    end
  end

  # A title with the characters a fuzzy search matched marked.
  def search_marked_title(title, marks)
    return title if marks.empty?

    marked = marks.to_set
    safe_join(title.each_char.with_index.map { |char, at| marked.include?(at) ? tag.mark(char) : char })
  end
end
