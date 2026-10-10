# frozen_string_literal: true

# GET /api/v1/pages[?locale=fr] and /api/v1/pages/<path> — live pages, blocks
# expanded.
class Api::V1::PagesController < Api::V1::BaseController
  requires_capability "pages:read", only: [:index, :show]

  def index
    scope = Page.live.includes(:translation_group, :category, :tags).order(:id)
    scope = scope.where(locale: params[:locale]) if params[:locale].present?
    @pages = paginate(scope).to_a
    @assets = included_assets(pages: @pages)
    cache_tags("pages", @pages.map { "page:#{it.path}" }, @pages.flat_map { Page::BlockExpansion.cache_tags(it.blocks) })
  end

  def show
    @page = Page.live.find_by!(path: params[:path])
    @assets = included_assets(pages: [@page])
    # And what its blocks pull in, so publishing an entry purges the pages listing it.
    cache_tags("page:#{@page.path}", Page::BlockExpansion.cache_tags(@page.blocks))
  end
end
