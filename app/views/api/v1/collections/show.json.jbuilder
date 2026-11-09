# frozen_string_literal: true

# `locals:`, not `collection:` -- jbuilder reads a bare `collection:` as a list to render each of.
json.data { json.partial! "api/v1/collections/collection", locals: {collection: @collection} }
json.meta({})
