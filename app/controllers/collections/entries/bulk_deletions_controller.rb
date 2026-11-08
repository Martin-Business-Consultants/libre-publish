# frozen_string_literal: true

# A collection's ticked entries to the trash in one go.
class Collections::Entries::BulkDeletionsController < ApplicationController
  include BulkSlugs

  include CollectionScoped

  requires_capability "entries:delete", only: :create

  def create
    slugs = bulk_slugs
    entries = CollectionEntry.trash_all(@collection.entries.where(slug: slugs).to_a, collection: @collection)
    redirect_to collection_entries_path(@collection.slug), notice: "#{entries.size} #{"entry".pluralize(entries.size)} moved to trash"
  end
end
