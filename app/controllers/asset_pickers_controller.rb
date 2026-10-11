# frozen_string_literal: true

# The picker a content form's asset fields open: the file manager's library
# in a turbo frame — every file, newest first, or one folder's; search; and
# uploading straight into it. Further pages load as the sheet scrolls
# (?page=2, the next grid and its own next link). Picking
# an asset is done in the browser (asset-picker controller); the field stores
# the asset's id, as it always has.
class AssetPickersController < ApplicationController
  requires_capability "assets:read",  only: :show
  requires_capability "assets:write", only: :create

  PER_PAGE = 60

  def show
    load_library
    render :page, layout: false if @page > 1
  end

  # files[]: signed ids from direct uploads (or the files themselves).
  def create
    @folder = chosen_folder
    files = Array(params[:files]).compact_blank
    @uploaded = Asset.upload(files, folder: @folder || "/")
    saved = @uploaded.select(&:persisted?)
    @upload_errors = (@uploaded - saved).map { |asset| "#{asset.file.filename}: #{asset.errors.full_messages.to_sentence}" }
    load_library
    render :show, status: (@upload_errors.any? ? :unprocessable_content : :ok)
  rescue AssetFolders::InvalidPath => e
    @upload_errors = [e.message]
    load_library
    render :show, status: :unprocessable_content
  end

  private

  # @folder is nil for every folder.
  def load_library
    @query = params[:q].to_s.strip
    @folder ||= chosen_folder
    @folders = (["/"] + AssetFolders.all(Asset.distinct.pluck(:folder))).uniq
    @page = [params[:page].to_i, 1].max
    assets = Asset.with_attached_file.order(created_at: :desc, id: :desc)
    assets = assets.where(folder: @folder) if @folder
    assets = assets.matching(@query) if @query.present?
    page = assets.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = page.size > PER_PAGE
    @assets = page.first(PER_PAGE)
  end

  def chosen_folder
    AssetFolders.normalize(params[:folder]) if params[:folder].present?
  rescue AssetFolders::InvalidPath
    nil
  end
end
