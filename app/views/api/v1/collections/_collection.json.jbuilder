# frozen_string_literal: true

json.extract! collection, :id, :slug, :name, :enable_blocks
json.fields collection.fields
