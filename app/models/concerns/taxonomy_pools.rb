# frozen_string_literal: true

# A category (one) and tags (many), each an entry of a pool collection. The
# including model says which collections are its pools (`category_pool`,
# `tag_pool`); with no pool, it can't be categorized or tagged, which stops an
# editor quietly assigning into a pool that doesn't exist.
module TaxonomyPools
  extend ActiveSupport::Concern

  included do
    belongs_to :category, class_name: "CollectionEntry", foreign_key: :category_entry_id, optional: true
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :tags, through: :taggings, source: :tag_entry
  end

  private

  # The missing-pool messages name the page pools for entries too, as they
  # always have.
  def validate_category_in_pool
    return if category_entry_id.blank?

    pool = category_pool
    if pool.nil?
      errors.add(:category, "cannot be set — no '#{Page::Taxonomized::PAGE_CATEGORIES_SLUG}' collection exists")
    elsif category.nil? || category.collection_id != pool.id
      errors.add(:category, "must come from the '#{pool.slug}' collection")
    end
  end

  def validate_tags_in_pool
    return if taggings.none? && tags.empty?

    pool = tag_pool
    if pool.nil?
      errors.add(:tags, "cannot be set — no '#{Page::Taxonomized::PAGE_TAGS_SLUG}' collection exists")
    elsif tags.any? { it.collection_id != pool.id }
      errors.add(:tags, "must all come from the '#{pool.slug}' collection")
    end
  end
end
