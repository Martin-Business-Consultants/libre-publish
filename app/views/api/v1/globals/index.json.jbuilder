# frozen_string_literal: true

json.data @globals, partial: "api/v1/globals/global", as: :global
json.meta({total: @globals.size})
json.partial! "api/v1/shared/included", assets: @assets
