# frozen_string_literal: true

json.data { json.partial! "api/v1/globals/global", global: @global }
json.meta({})
json.partial! "api/v1/shared/included", assets: @assets
