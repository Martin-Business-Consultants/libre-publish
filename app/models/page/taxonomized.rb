# frozen_string_literal: true

# A page's category and tags (TaxonomyPools), from the well-known pool
# collections "page-categories" and "page-tags". Collections point at their
# pools through ids; pages don't need that indirection, since one shared pool
# per side is enough.
module Page::Taxonomized
  extend ActiveSupport::Concern
  include TaxonomyPools

  PAGE_CATEGORIES_SLUG = "page-categories"
  PAGE_TAGS_SLUG = "page-tags"

  def category_pool
    Collection.find_by(slug: PAGE_CATEGORIES_SLUG)
  end

  def tag_pool
    Collection.find_by(slug: PAGE_TAGS_SLUG)
  end
end
