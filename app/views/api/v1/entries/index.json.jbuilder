# frozen_string_literal: true

json.data @entries, partial: "api/v1/entries/entry", as: :entry
json.meta @meta
json.partial! "api/v1/shared/included", assets: @assets
