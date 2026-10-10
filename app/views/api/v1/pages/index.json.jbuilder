# frozen_string_literal: true

json.data @pages, partial: "api/v1/pages/page", as: :page
json.meta @meta
json.partial! "api/v1/shared/included", assets: @assets
