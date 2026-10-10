# frozen_string_literal: true

# GET /api/v1/collections/<slug>/entries[?locale=fr] and …/entries/<slug> —
# a collection's live entries.
class Api::V1::EntriesController < Api::V1::BaseController
  requires_capability "entries:read", only: [:index, :show]

  before_action { @collection = Collection.find_by!(slug: params[:collection_slug]) }

  def index
    scope = @collection.entries.live.includes(:translation_group, :category, :tags).order(:id)
    scope = scope.where(locale: params[:locale]) if params[:locale].present?
    @entries = paginate(scope).to_a
    @assets = included_assets(entries: @entries)
    cache_tags("collection:#{@collection.slug}", @entries.map { "entry:#{@collection.slug}/#{it.slug}" })
  end

  def show
    @entry = @collection.entries.live.find_by!(slug: params[:slug])
    @assets = included_assets(entries: [@entry])
    cache_tags("entry:#{@collection.slug}/#{@entry.slug}")
  end
end
