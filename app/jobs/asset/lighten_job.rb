# frozen_string_literal: true

# An upload over the site's image limits (ImageLimits) made a lighter WebP
# as it arrives (Asset::Optimizable#lighten_now), in the background so the
# upload isn't kept waiting.
class Asset::LightenJob < ApplicationJob
  queue_as :default

  def perform(asset_id)
    Asset.find_by(id: asset_id)&.lighten_now
  end
end
