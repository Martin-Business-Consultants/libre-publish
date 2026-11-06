# frozen_string_literal: true

# GET /api/v1/schema — JSON Schema for everything a site renders: each block
# type's data, each collection's entry fields, each global's data, the pages
# that have fields of their own, and SEO (DeliverySchema). A build generates
# its types from it and pins its digest (meta.schema_digest).
class Api::V1::SchemasController < Api::V1::BaseController
  requires_capability "block_types:read", only: :show

  def show
    @schema = DeliverySchema.current
    cache_tags("schema")
  end
end
