# frozen_string_literal: true

# A list screen's search (WordPress's ?s=): `search_on :title, :slug` gives the
# model `search_list(term)`. A model in the search index (SearchIndexed) is
# searched there, by everything it indexes; a term too short for it, or a
# model that isn't indexed (a plugin's), by rows whose named columns contain
# the term, case folded as SQLite's LIKE does. A blank term matches
# everything, so a list can always call it. Either way it's a relation, so
# the list's filters, order and pagination apply as before.
module ListSearchable
  extend ActiveSupport::Concern

  class_methods do
    def search_on(*columns)
      scope :search_list, ->(term) {
        text = term.to_s.strip
        if text.empty?
          all
        elsif self < SearchIndexed && text.length >= SearchIndexed::MIN_LENGTH
          where(id: search_index_ids(text))
        else
          pattern = "%#{sanitize_sql_like(text)}%"
          where(columns.map { |column| arel_table[column].matches(pattern, "\\") }.reduce(:or))
        end
      }
    end
  end
end
