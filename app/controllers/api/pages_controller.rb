# frozen_string_literal: true

# Pages over the API. The schema and the bulk operations are resources of
# their own under Api::Pages; the JSON is app/views/api/pages.
class Api::PagesController < Api::BaseController
  include Api::PublishCapability
  include Api::HeldWrites
  include Api::LockVersioned

  enforce_authorization
  requires_capability "pages:read",   only: [:index, :show]
  requires_capability "pages:write",  only: [:create, :update]
  requires_capability "pages:delete", only: :destroy

  before_action :set_page, only: [:show, :update, :destroy]
  advertises_lock_version :@page

  # What an agent should do next, when it asks for the envelope. These are the
  # exact commands — a suggestion it has to translate is a suggestion it gets
  # wrong.
  agent_summary(:index) do |payload|
    total = payload["total"].to_i
    paged = total > payload["per"].to_i ? " · page #{payload["page"]}" : ""
    "#{total} #{"page".pluralize(total)}#{paged}."
  end
  agent_breadcrumbs(:index) do |payload|
    # Name a page that is actually in the list. "cms page <path>" asks the
    # caller to pick one and hope; this one runs as printed.
    first = payload.dig("pages", 0)
    path = first&.dig("path") || first&.dig("slug") || "<path>"
    [crumb("Open one, blocks expanded", "cms page #{path}"),
      crumb("Only drafts", "cms pages --status draft"),
      crumb("Publish one", "cms publish #{path}")]
  end
  agent_summary(:show) { |payload| "#{payload.dig("page", "title")} — #{payload.dig("page", "status")}" }
  agent_breadcrumbs(:show) do |payload|
    path = payload.dig("page", "path") || payload.dig("page", "slug")
    [crumb("Edit it", %(cms patch /pages/#{path} '{"page":{"title":"…"}}')),
     crumb("Publish it", "cms publish #{path}"),
     crumb("What links here, before deleting it", "cms refs Page #{payload.dig("page", "id")}")]
  end
  agent_summary(:create, :update) do |payload|
    page = payload["page"] or next nil
    "#{page["title"]} (#{page["path"] || page["slug"]}) — #{page["status"]}."
  end
  agent_breadcrumbs(:create, :update) do |payload|
    path = payload.dig("page", "path") || payload.dig("page", "slug")
    [crumb("See it back", "cms page #{path}"), crumb("Publish it", "cms publish #{path}")]
  end

  def index
    pages = Page.order(updated_at: :desc)
    pages = pages.live if published_only?("pages")
    pages = pages.where(status: params[:status]) if params[:status].present?
    pages = pages.where(locale: params[:locale]) if params[:locale].present?

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per = (params[:per] || 25).to_i.clamp(1, 100)
    @total = pages.count
    @pages = pages.offset((@page_number - 1) * @per).limit(@per)
  end

  def show
    @blocks = @page.expanded_blocks
    @assets = MediaLibrary.resolve(:pages, [@page]) if resolve_assets?
  end

  def create
    @page = Page.new(page_params)
    return if hold_write(:create, @page, page_params, prefix: "pages")

    require_publish_capability!(@page, prefix: "pages")
    @page.save!
    @page.track_creation
    render :show, status: :created
  end

  def update
    prior_status = @page.status
    @page.assign_attributes(page_params)
    return if hold_write(:update, @page, page_params, prefix: "pages")

    require_publish_capability!(@page, prefix: "pages")
    expect_lock_version(@page, :page)
    @page.save!
    @page.track_update(from: prior_status)
    render :show
  end

  # Soft delete, matching the admin: the page lands in the trash and is
  # restorable through /api/trash for the retention window.
  # `?permanent=true` skips the trash for a caller that means it.
  def destroy
    return if hold_write(:destroy, @page, {}, prefix: "pages")

    if permanent?
      require_capability!("trash:write")
      @page.purge
    else
      @page.trash
    end

    head :no_content
  end

  private

  def set_page
    @page = (published_only?("pages") ? Page.live : Page).find_by!(path: params[:slug])
  end

  def resolve_assets?
    %w[1 true yes assets].include?(params[:resolve].to_s)
  end

  def permanent?
    %w[1 true yes].include?(params[:permanent].to_s)
  end

  # `parent_id` is permitted to match the admin. Without it the API silently
  # dropped the key, so API-created hierarchies flattened and consumers had to
  # fake nesting by stuffing the real path into frontmatter.
  def page_params
    params.require(:page).permit(
      :slug, :title, :status, :locale, :published_at, :category_entry_id, :parent_id,
      tag_ids: [],
      blocks: [:id, :type, :version, {data: {}}],
      frontmatter: {},
      seo: {}
    )
  end
end
