# frozen_string_literal: true

# An asset as the API hands it to a site (/api/assets, ?resolve=assets):
# absolute URLs on the CMS's own host — Site.url_options, from APP_HOST and
# APP_PROTOCOL, never the public site's address — so a site on another
# domain (an Astro build, a Worker) can fetch them as remote images, plus an
# image's width and height and a few width-limited renditions. The URLs are
# the Go core's, /files/<key>/<name> and /files/<key>/w<width>/<name>
# (FilesController), which @librepublish/astro allows as remote images and
# copies into a site's build; the Active Storage URLs they lead to keep
# working.
#
#   asset.delivery
#   # => {"url" => "https://cms.acme.com/files/<key>/logo.png",
#   #     "original" => (the same), "width" => 1200, "height" => 630,
#   #     "variants" => {"w640" => "https://cms.acme.com/files/<key>/w640/logo.png", …}, …}
#
# The admin's own pages keep using #url and #thumb_url, which are paths.
module Asset::Delivery
  extend ActiveSupport::Concern

  # The renditions every image offers, by width; height follows the image.
  DELIVERY_WIDTHS = [640, 1280, 1920].freeze
  THUMB_WIDTH = 256
  # Every width /files/<key>/w<width>/<name> makes: the renditions, the
  # thumbnail and the srcset's.
  RENDITION_WIDTHS = (DELIVERY_WIDTHS + [THUMB_WIDTH] + Asset::Renditions::RESPONSIVE_WIDTHS).uniq.sort.freeze

  def absolute_url
    file_url if file.attached?
  end

  # From the blob's analysis, made the first time they're asked for if Active
  # Storage's background analysis hasn't run yet; nil for a file that isn't an
  # image, or one the analyzer can't read (an SVG may have none).
  def width = measurements["width"]

  def height = measurements["height"]

  # {"w640" => url, …}: empty for an SVG, a non-image, or an install whose
  # libvips can't make variants (ApplicationHelper.variants_supported?).
  def variants
    return {} unless variantable? && ApplicationHelper.variants_supported?

    DELIVERY_WIDTHS.to_h { |w| ["w#{w}", file_url(w)] }
  end

  def delivery
    {
      "id" => id, "url" => absolute_url, "original" => absolute_url,
      "filename" => filename, "content_type" => content_type, "byte_size" => byte_size,
      "width" => width, "height" => height, "alt" => alt, "folder" => folder
    }.tap do |summary|
      next unless image?

      summary["variants"] = variants
      summary["thumb_url"] = variantable? && ApplicationHelper.variants_supported? ? file_url(THUMB_WIDTH) : absolute_url
      summary["srcset"] = srcset.map { it.merge(url: file_url(it[:width])) }
      summary["focal_x"] = focal_x
      summary["focal_y"] = focal_y
    end
  end

  private

  def measurements
    @measurements ||= begin
      return {} unless image? && file.attached?

      file.analyze unless file.analyzed?
      file.metadata
    rescue StandardError => e
      Rails.logger.warn("[Asset] couldn't measure asset #{id}: #{e.class}: #{e.message}")
      {}
    end
  end

  # /files/<key>/<name>, or a rendition at a width: /files/<key>/w<width>/<name>.
  def file_url(width = nil)
    Rails.application.routes.url_helpers.delivered_file_url(key: file.blob.key, rendition: ("w#{width}" if width),
      filename: file.filename.to_s, **Site.url_options)
  end
end
