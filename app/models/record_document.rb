# frozen_string_literal: true

# A row of the admin's search index (config/search.rb's :records): which
# record it is. Its text is in record_documents_fts. ActiveSearch writes and
# reads it (SearchIndexed); nothing else should.
class RecordDocument < ApplicationRecord
end
