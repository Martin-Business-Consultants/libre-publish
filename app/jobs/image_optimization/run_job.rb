# frozen_string_literal: true

# Runs the Image Optimizer (ImageOptimization#run) in the background.
class ImageOptimization::RunJob < ApplicationJob
  queue_as :default

  def perform(optimization_id)
    ImageOptimization.find(optimization_id).run
  end
end
