# frozen_string_literal: true

# The admin side of the sitemap over the API: the full tree, rows excluded
# from the published sitemap included (GET /api/sitemap/entries), and a
# narrow patch for one row's sitemap settings (PATCH /api/sitemap/:source/:id,
# `source` being "page" or "collection_entry"). Content edits go through the
# page and entry endpoints; this is for "noindex this, bump that one's
# priority".
class Api::SitemapEntriesController < Api::BaseController
  requires_capability "pages:read",  only: :index
  requires_capability "pages:write", only: :update

  # Sitemap settings are a change to the page or entry: while a plugin holds
  # API writes for a person (Approvals), they go through the record's own
  # endpoint, one at a time, as any other change does.
  include Api::HeldWrites
  refuse_while_held only: :update

  def index
    sitemap = Sitemap.new
    @all = sitemap.all_entries
    @included = sitemap.entries
    # A token that can't write content (the site's own) sees only what's live.
    @all = @all.select { it.status == "published" } if published_only?("pages")
  end

  def update
    @record = Sitemap.record_for(params[:source], params[:id])
    return render(json: {error: "not_found"}, status: :not_found) unless @record

    settings = params.require(:entry).permit(:status, *Sitemapped::SETTINGS)

    if settings.key?(:status) && !Page::STATUSES.include?(settings[:status])
      render json: {error: "invalid", message: "status must be one of #{Page::STATUSES.join(", ")}"},
        status: :unprocessable_content
    else
      require_capability!("entries:write") if params[:source].to_s == "collection_entry"
      # A status change, or any change to what's live, takes publishing it.
      if (settings.key?(:status) && settings[:status] != @record.status) || @record.try(:status) == "published"
        require_capability!(Sitemap.publish_capability(params[:source]))
      end

      @record.status = settings[:status] if settings.key?(:status)
      @record.change_sitemap_settings(settings.except(:status))
      @record.save!

      @record.track_sitemap_update(source: params[:source])
    end
  end
end
