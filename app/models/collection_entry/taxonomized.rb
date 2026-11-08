# frozen_string_literal: true

# An entry's category and tags (TaxonomyPools), from the pool collections its
# own collection names (`categories_collection`, `tags_collection`).
module CollectionEntry::Taxonomized
  extend ActiveSupport::Concern
  include TaxonomyPools

  def category_pool
    collection&.categories_collection
  end

  def tag_pool
    collection&.tags_collection
  end
end
