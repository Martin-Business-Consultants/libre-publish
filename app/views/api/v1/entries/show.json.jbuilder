# frozen_string_literal: true

json.data { json.partial! "api/v1/entries/entry", entry: @entry }
json.meta({})
json.partial! "api/v1/shared/included", assets: @assets
