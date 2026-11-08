# frozen_string_literal: true

json.extract! collection, :id, :slug, :name, :enable_blocks, :routable
json.fields collection.fields
