# frozen_string_literal: true

# Reverse lookup: what links to this thing?
#
#   GET /api/references?ref_type=asset&ref_id=42[&kind=image][&page=1&per=50]
#
# One row per owner (a page that uses an asset twice is listed once), paged
# by reference rows.
class Api::ReferencesController < Api::BaseController
  requires_capability "pages:read", only: :index

  PER_PAGE_DEFAULT = 50
  PER_PAGE_MAX     = 200

  def index
    @ref_type = params[:ref_type].to_s
    @ref_id = params[:ref_id].to_s
    if @ref_type.empty?
      render json: {error: "ref_type is required"}, status: :bad_request
    elsif @ref_id.empty?
      render json: {error: "ref_id is required"}, status: :bad_request
    else
      @page = [params[:page].to_i, 1].max
      @per = params[:per].to_i <= 0 ? PER_PAGE_DEFAULT : [params[:per].to_i, PER_PAGE_MAX].min
      @references, @total = ContentReference.owners_of(ref_type: @ref_type, ref_id: @ref_id, kind: params[:kind],
        page: @page, per: @per, owners: readable_owners)
    end
  end

  private

  # The owners this token may see: each kind it reads, and of pages and
  # entries only the live ones unless it can write them.
  def readable_owners
    owners = {}
    owners["Page"] = published_only?("pages") ? Page.live : Page.all if granted?("pages:read")
    owners["CollectionEntry"] = published_only?("entries") ? CollectionEntry.live : CollectionEntry.all if granted?("entries:read")
    owners["Global"] = Global.all if granted?("globals:read")
    owners
  end
end
