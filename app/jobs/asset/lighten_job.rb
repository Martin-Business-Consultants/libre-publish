# frozen_string_literal: true

# An upload over the site's image limits (ImageLimits) made a lighter WebP
# as it arrives (Asset::Optimizable), in the background so the upload isn't
# kept waiting.
class Asset::LightenJob < ApplicationJob
  queue_as :default

  def perform(asset_id)
    asset = Asset.find_by(id: asset_id)
    return if asset.nil? || asset.deleted_at || asset.optimized?

    asset.file.analyze unless asset.file.analyzed?
    asset.optimize! if asset.optimizable?
  end
end
