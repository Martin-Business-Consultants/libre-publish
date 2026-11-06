# frozen_string_literal: true

# OPTIONS /api/v1/pages and /api/v1/pages/<path> — what the resource answers,
# as JSON Schema (DeliverySchema::Resource): a page's frontmatter its own
# fields, when it has them.
class Api::V1::PageSchemasController < Api::V1::BaseController
  before_action :require_pages_served
  requires_capability "pages:read", only: :show

  def show
    page = Page.live.find_by!(path: params[:path]) if params[:path].present?
    describe DeliverySchema::Resource.pages(page: page, list: page.nil?)
  end
end
