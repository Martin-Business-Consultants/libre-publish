# frozen_string_literal: true

# GET /api/v1/globals and /api/v1/globals/<slug> — nav, footer and the rest.
class Api::V1::GlobalsController < Api::V1::BaseController
  requires_capability "globals:read", only: [:index, :show]

  def index
    @globals = Global.order(:slug).to_a
    @assets = included_assets(globals: @globals)
    cache_tags(@globals.map { "global:#{it.slug}" })
  end

  def show
    @global = Global.find_by!(slug: params[:slug])
    @assets = included_assets(globals: [@global])
    cache_tags("global:#{@global.slug}")
  end
end
