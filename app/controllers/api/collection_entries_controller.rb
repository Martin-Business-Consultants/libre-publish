# frozen_string_literal: true

# A collection's entries over the API. Merging one field, a Build board move
# and the bulk operations are resources of their own under
# Api::Collections::Entries; the JSON is app/views/api/collection_entries.
class Api::CollectionEntriesController < Api::BaseController
  include CollectionScoped
  include Api::PublishCapability
  include Api::HeldWrites
  include Api::LockVersioned

  enforce_authorization
  requires_capability "entries:read",   only: [:index, :show]
  requires_capability "entries:write",  only: [:create, :update]
  requires_capability "entries:delete", only: :destroy

  before_action :set_entry, only: [:show, :update, :destroy]
  advertises_lock_version :@entry

  agent_breadcrumbs(:index) do
    [crumb("Open one", "cms entry #{params[:collection_id] || "<collection>"} <slug>"),
     crumb("Only drafts", "cms entries #{params[:collection_id] || "<collection>"} --status draft"),
     crumb("Publish some", "cms entry-status #{params[:collection_id] || "<collection>"} published <slug>…")]
  end
  agent_breadcrumbs(:show) do |payload|
    collection = params[:collection_id]
    slug = payload.dig("entry", "slug")
    [crumb("Edit it", %(cms patch /collections/#{collection}/entries/#{slug} '{"entry":{}}')),
     crumb("Publish it", "cms entry-status #{collection} published #{slug}"),
     crumb("Back to the collection", "cms entries #{collection}")]
  end

  def index
    entries = @collection.entries.order(updated_at: :desc)
    entries = entries.live if published_only?("entries")
    entries = entries.where(status: params[:status]) if params[:status].present?

    @page_number = (params[:page] || 1).to_i.clamp(1, 10_000)
    @per = (params[:per] || 25).to_i.clamp(1, 100)
    @total = entries.count
    @entries = entries.offset((@page_number - 1) * @per).limit(@per)
    @assets = MediaLibrary.resolve(:entries, @entries) if resolve_assets?
  end

  def show
    @assets = MediaLibrary.resolve(:entries, [@entry]) if resolve_assets?
  end

  def create
    @entry = @collection.entries.new(entry_params)
    return if hold_write(:create, @entry, entry_params, prefix: "entries")

    require_publish_capability!(@entry, prefix: "entries")
    @entry.save!
    @entry.track_creation
    render :show, status: :created
  end

  def update
    prior_status = @entry.status
    @entry.assign_attributes(entry_params)
    return if hold_write(:update, @entry, entry_params, prefix: "entries")

    require_publish_capability!(@entry, prefix: "entries")
    expect_lock_version(@entry, :entry)
    @entry.save!
    @entry.track_update(from: prior_status)
    render :show
  end

  # Soft-delete, matching the admin UI: the entry lands in the trash and is
  # restorable via /api/trash. `?permanent=true` skips it.
  def destroy
    return if hold_write(:destroy, @entry, {}, prefix: "entries")

    if permanent?
      require_capability!("trash:write")
      @entry.purge
    else
      @entry.trash
    end

    head :no_content
  end

  private

  def set_entry
    @entry = (published_only?("entries") ? @collection.entries.live : @collection.entries).find_by!(slug: params[:slug])
  end

  def permanent?
    %w[1 true yes].include?(params[:permanent].to_s)
  end

  def resolve_assets?
    %w[1 true yes assets].include?(params[:resolve].to_s)
  end

  def entry_params
    params.require(:entry).permit(
      :slug, :title, :status, :locale, :body_markdown, :published_at, :category_entry_id,
      tag_ids: [],
      blocks: [:id, :type, :version, {data: {}}],
      frontmatter: {},
      seo: {}
    )
  end
end
