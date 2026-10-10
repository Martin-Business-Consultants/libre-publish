# frozen_string_literal: true

# GET /api/v1/collections and /api/v1/collections/<slug> — the collections and
# their fields (their schema is /api/v1/schema).
class Api::V1::CollectionsController < Api::V1::BaseController
  requires_capability "collections:read", only: [:index, :show]

  def index
    @collections = Collection.order(:slug).to_a
    cache_tags(@collections.map { "collection:#{it.slug}" })
  end

  def show
    @collection = Collection.find_by!(slug: params[:slug])
    cache_tags("collection:#{@collection.slug}")
  end
end
