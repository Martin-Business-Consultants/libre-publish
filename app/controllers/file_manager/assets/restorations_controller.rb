# frozen_string_literal: true

# "Restore original" on an optimized image (Asset::Optimizable): the file it
# had before the Image Optimizer made it a WebP, back in place.
class FileManager::Assets::RestorationsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:write", only: :create

  def create
    asset = Asset.find(params[:asset_id])
    asset.restore_original!
    asset.track_update
    redirect_to file_manager_asset_path(asset), notice: "The original #{asset.filename} is back."
  end
end
