# frozen_string_literal: true

# OPTIONS /api/v1/collections/<slug>/entries and …/entries/<slug> — what the
# resource answers, as JSON Schema (DeliverySchema::Resource).
class Api::V1::EntrySchemasController < Api::V1::BaseController
  requires_capability "entries:read", only: :show

  before_action { @collection = Collection.find_by!(slug: params[:collection_slug]) }
  before_action { require_collection_served(@collection) }

  def show
    @collection.entries.live.find_by!(slug: params[:slug]) if params[:slug].present?
    describe DeliverySchema::Resource.entries(@collection, list: params[:slug].blank?)
  end
end
