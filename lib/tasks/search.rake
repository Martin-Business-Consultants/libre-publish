# frozen_string_literal: true

# Puts every record back in the admin's search index (SearchIndexed,
# config/search.rb). Records are indexed as they're saved; use this when
# that was bypassed: a bulk import, raw SQL, insert_all.
#
#   bin/rails search:reindex
namespace :search do
  desc "Put every page, entry, global and the rest back in the search index"
  task reindex: :environment do
    count = SearchIndexed.reindex_all
    puts "Indexed #{count} records across #{SearchIndexed.models.map(&:name).sort.join(", ")}"
  end
end
