# frozen_string_literal: true

# GET /api/v1/schema — JSON Schema for everything a site renders: each block
# type's data, each collection's entry fields, each global's data, the pages
# that have fields of their own, and SEO. A build generates its types from it.
class Api::V1::SchemasController < Api::V1::BaseController
  requires_capability "block_types:read", only: :show

  def show
    @block_types = BlockType.order(:slug).to_a
    @collections = Collection.order(:slug).to_a
    @globals = Global.order(:slug).to_a
    @pages = Page.live.order(:path).select { it.fields.any? }
    cache_tags("schema")
  end
end
