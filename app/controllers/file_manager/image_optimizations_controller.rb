# frozen_string_literal: true

# The Media Library's Image Optimizer: starts a run (ImageOptimization) in
# the background and shows how it's going.
class FileManager::ImageOptimizationsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:write", only: [:create, :show]

  def create
    redirect_to file_manager_image_optimization_path(ImageOptimization.start)
  rescue ImageOptimization::Busy
    redirect_to file_manager_image_optimization_path(ImageOptimization.current)
  end

  def show
    @optimization = ImageOptimization.find(params[:id])
  end
end
