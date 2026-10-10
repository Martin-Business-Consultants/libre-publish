# frozen_string_literal: true

json.data @collections, partial: "api/v1/collections/collection", as: :collection
json.meta({total: @collections.size})
