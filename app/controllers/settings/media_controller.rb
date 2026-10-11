# frozen_string_literal: true

# Settings › Media (ImageLimits): how heavy an image on the website may be,
# and whether uploads over that are made lighter as they arrive.
class Settings::MediaController < Settings::BaseController
  requires_capability "settings:read",  only: :show
  requires_capability "settings:write", only: :update

  def show
    @limits = {"max_kb" => ImageLimits.max_kb, "max_side" => ImageLimits.max_side, "optimize_uploads" => ImageLimits.optimize_uploads?}
    @over = Asset.optimizable_candidates.count { it.optimizable? && !it.optimized? }
  end

  def update
    ImageLimits.update(params.fetch(:media, {}).permit(:max_kb, :max_side, :optimize_uploads).to_h)
    Event.record("settings.media_updated", fields: %w[max_kb max_side optimize_uploads])
    redirect_to settings_media_path, notice: "Media settings saved"
  end
end
