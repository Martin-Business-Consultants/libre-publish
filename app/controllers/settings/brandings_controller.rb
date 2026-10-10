# frozen_string_literal: true

# Settings › Branding: the one page for how things look and sound. This
# browser's appearance (anyone), then the workspace's visual identity —
# logo, favicon, colors, font, corners, shadow (Branding) — and its brand
# context (Settings::BrandsController), which need settings:read.
#
# Branding is stored in the `settings` key/value table (not `globals`), since
# it's admin-only configuration, not editorially-authored content. The public
# site reads it; the admin wears the color and font too (/branding.css).
# Corners are the site's alone: the admin always uses one 3px radius
# (--radius in _global.css).
class Settings::BrandingsController < Settings::BaseController
  include Settings::BrandingScreen

  # The page is anyone's (appearance); saving the workspace's branding takes
  # settings:write, checked in update.
  skip_authorization

  IMAGE_FOLDER = "/branding"

  def show
    prepare_branding
  end

  def update
    raise Authorization::Forbidden, "settings:write" unless Current.user.can?("settings:write")

    attributes = params.require(:branding).permit(*Branding::PERMITTED, :logo_file, :favicon_file).to_h
    %w[logo favicon].each do |kind|
      file = attributes.delete("#{kind}_file")
      next if file.blank?
      return render_branding(alert: "The #{kind} has to be an image.") unless file.content_type.to_s.start_with?("image/")

      attributes["#{kind}_id"] = MediaLibrary.upload(file, folder: IMAGE_FOLDER)&.id
    end

    record = Branding.save(attributes)
    Event.record("settings.branding_updated", keys: record.data.keys.sort)
    redirect_to settings_branding_path(anchor: "identity"), notice: "Branding saved"
  end
end
