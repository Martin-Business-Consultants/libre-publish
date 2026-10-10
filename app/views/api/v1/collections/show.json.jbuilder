# frozen_string_literal: true

json.data { json.partial! "api/v1/collections/collection", collection: @collection }
json.meta({})
