# frozen_string_literal: true

# OPTIONS /api/v1/globals/<slug> — what the resource answers, as JSON Schema
# (DeliverySchema::Resource).
class Api::V1::GlobalSchemasController < Api::V1::BaseController
  before_action :require_pages_served
  requires_capability "globals:read", only: :show

  def show
    describe DeliverySchema::Resource.global(Global.find_by!(slug: params[:slug]))
  end
end
