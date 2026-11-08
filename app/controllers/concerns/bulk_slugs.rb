# frozen_string_literal: true

# Bulk operations, in the admin and over the API, address records by slug
# (pages by path). The API reports missing slugs rather than skipping them: a
# bulk change that quietly did nothing for half its input is worse than an
# error.
module BulkSlugs
  private

  def bulk_slugs
    Array(params[:slugs]).map(&:to_s).reject(&:empty?)
  end

  def missing_slugs(found)
    bulk_slugs - found.map(&:slug)
  end
end
