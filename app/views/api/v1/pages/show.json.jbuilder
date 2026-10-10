# frozen_string_literal: true

json.data { json.partial! "api/v1/pages/page", page: @page }
json.meta({})
json.partial! "api/v1/shared/included", assets: @assets
