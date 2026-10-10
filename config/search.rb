# frozen_string_literal: true

# One index for everything the admin searches (Searchable): pages, entries,
# collections, globals, block types, users, roles, redirects and the audit
# log, each as a title and a body of text. A list screen's search box
# narrows it to its own model (search_list); the admin bar's search reads
# across it (GlobalSearch). The document table's FTS5 index is a trigram
# one, so "pri" finds "Pricing" as the LIKE search before it did.
ActiveSearch.define_index(:records, polymorphic: true) do
  text :title
  text :body
end
