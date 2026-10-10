# frozen_string_literal: true

# Content › Pages: the page tree, a page's form (its settings, fields, blocks
# and SEO), and delete. Bulk changes and the schema are resources under
# Pages::. Changing a published page, or publishing one, needs pages:publish
# (ContentEditing).
class PagesController < ApplicationController
  include ContentEditing

  requires_capability "pages:read",   only: :index
  requires_capability "pages:write",  only: [:new, :create, :edit, :update]
  requires_capability "pages:delete", only: :destroy

  before_action :set_page, only: [:edit, :update, :destroy]

  def index
    @status = params[:status].presence_in(Page::STATUSES)
    @locale = params[:locale].presence
    @locales = Page.distinct.order(:locale).pluck(:locale)
    @status_counts = Page.group(:status).count
    @pages = paginate(filtered_pages)
    @new_page ||= Page.new(status: "draft", locale: "en")
  end

  def new
    @page = Page.new(status: "draft", locale: "en", blocks: [], frontmatter: {}, seo: {})
  end

  # The list's New page dialog posts a title, slug and optional template; the
  # full new-page form posts everything the edit form does.
  def create
    @page = Page.new
    @page.assign_attributes(page_attributes(@page))
    template = Page.template(params[:template].to_s.presence)
    @page.apply_template(template) if template
    @page.slug = @page.title.to_s.parameterize if @page.slug.blank?

    if save_content(@page, prefix: "pages")
      @page.track_creation(template: template)
      notice = template ? "Page created from “#{template["title"]}” template" : "Page created"
      redirect_to edit_page_path(@page.path), notice: notice
    elsif params[:from] == "dialog"
      @new_page = @page
      index
      render :index, status: :unprocessable_content
    else
      render :new, status: :unprocessable_content
    end
  rescue ContentForm::InvalidJson => e
    invalid_json(e, :new)
  end

  def edit
  end

  def update
    prior_status = @page.status
    if save_content(@page, page_attributes(@page), prefix: "pages")
      @page.track_update(from: prior_status)
      redirect_to edit_page_path(@page.path), notice: "Page saved"
    else
      render :edit, status: :unprocessable_content
    end
  rescue ContentForm::InvalidJson => e
    invalid_json(e, :edit)
  end

  def destroy
    @page.trash
    redirect_to pages_path, notice: "Page moved to trash"
  end

  private

  def set_page
    @page = Page.find_by!(path: params[:slug])
  end

  # What the form posted, read back into the page's attributes: its own
  # settings, then its fields, blocks and SEO through ContentForm.
  def page_attributes(page)
    attributes = params.require(:page).permit(:slug, :title, :status, :locale, :parent_id, :category_entry_id).to_h
    attributes["tag_ids"] = content_ids(:page, :tag_ids) unless content_ids(:page, :tag_ids).nil?
    %i[publish_at unpublish_at].each do |key|
      value = content_time(:page, key)
      attributes[key.to_s] = value unless value == :absent
    end
    attributes["frontmatter"] = decoded_content_object(:page, :frontmatter, page.fields, page.frontmatter)
    attributes["blocks"] = decoded_content_blocks(:page, page.blocks)
    attributes["seo"] = decoded_content_object(:page, :seo, SeoFields::ALL, page.seo)
    attributes
  end

  # A JSON-LD box that doesn't parse: show the form again with what was
  # typed and say where.
  def invalid_json(error, template)
    @invalid_json = {error.path => params.dig(:page, :seo, :json_ld).to_s}
    @page.valid?
    @page.errors.add(:seo, error.message)
    render template, status: :unprocessable_content
  end

  def filtered_pages
    pages = Page.order(:path).search_list(search_term)
    pages = pages.where(status: @status) if @status
    pages = pages.where(locale: @locale) if @locale
    pages
  end
end
