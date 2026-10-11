# frozen_string_literal: true

# The image editor (image-editor controller, in the editor's preview): the
# image to edit (show, JSON), and the edited one saved as a copy beside it
# (create): the same folder, alt text, caption and description, named
# "(edited)", so anything else that uses the original keeps it. The copy is
# made lighter as the Image Optimizer would (Asset::Optimizable).
class FileManager::Assets::ImageEditsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:read", only: :show
  requires_capability "assets:write", only: :create

  before_action :set_asset

  def show
    render json: {id: @asset.id, name: @asset.title, url: rails_blob_path(@asset.file, disposition: "inline"),
                  width: @asset.file.metadata["width"], height: @asset.file.metadata["height"]}
  end

  def create
    image = params.require(:image)
    unless image.respond_to?(:content_type) && image.content_type.to_s.start_with?("image/")
      return render json: {error: "An edited image is needed."}, status: :unprocessable_content
    end

    copy = Asset.create!(folder: @asset.folder, name: "#{@asset.title} (edited)", alt: @asset.alt, caption: @asset.caption,
      description: @asset.description, file: image)
    copy.file.analyze
    copy.optimize! if copy.optimizable?
    copy.reload.track_event(:created, folder: copy.folder)
    render json: {id: copy.id.to_s, name: copy.title, thumb: helpers.media_thumbnail(copy, size: 160)}, status: :created
  end

  private

  def set_asset
    @asset = Asset.find(params[:asset_id])
    head :unprocessable_content unless @asset.variantable?
  end
end
