# frozen_string_literal: true

# A record in the admin's search index (config/search.rb's :records,
# ActiveSearch), as a title and a body of text from #search_document. It's
# written on every save and removed on destroy, or when the record goes to
# the trash, inline: the index is a table in this database. A list screen's
# search box finds the model's records in it (ListSearchable#search_list),
# and the admin bar's search reads across every model (GlobalSearch).
#
#   class Redirect < ApplicationRecord
#     include SearchIndexed
#     def search_document = {title: source_path, body: [destination_url, notes].join("\n")}
#   end
module SearchIndexed
  extend ActiveSupport::Concern

  # Trigram matching needs three characters; a shorter term is matched with
  # LIKE (ListSearchable).
  MIN_LENGTH = 3

  included do
    has_search index: :records, async: false, serializer: :search_document, add_unless: :trashed_for_search?
  end

  class_methods do
    # The ids of this model's records whose text holds the term, any number.
    def search_index_ids(term)
      search(term).limit(nil).to_native_query.unscope(:order).pluck(:record_id).map(&:to_i)
    end
  end

  # Every model in the index, and each one's records put back in it: after a
  # bulk import, a raw-SQL change, or the index's own migration.
  def self.models
    Rails.application.eager_load! unless Rails.application.config.eager_load
    ActiveRecord::Base.descendants.select { it < SearchIndexed && !it.abstract_class? }
  end

  def self.reindex_all
    models.sum do |model|
      model.reset_column_information
      scope = model.respond_to?(:with_discarded) ? model.with_discarded : model.unscoped
      scope.find_each.count { it.reindex || true }
    end
  end

  private

  def trashed_for_search? = respond_to?(:deleted_at) && deleted_at.present?
end
