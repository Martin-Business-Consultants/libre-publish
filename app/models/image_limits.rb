# frozen_string_literal: true

# How heavy an image on the website may be (Settings › Media): the largest
# file, and the longest side in pixels. A JPEG, PNG or WebP over either is
# made a lighter WebP (Asset::Optimizable): as it's uploaded, unless the site
# turns that off, and by the Media Library's Image Optimizer for the images
# already there. Stored in the `media` setting; each site sets its own, from
# defaults that suit most sites.
module ImageLimits
  KEY = "media"
  DEFAULT_MAX_KB = 750
  DEFAULT_MAX_SIDE = 2560
  KB_RANGE = (100..10_000)
  SIDE_RANGE = (640..8000)

  module_function

  def settings = Setting.get(KEY)

  def max_kb = settings["max_kb"].to_i.presence_in(KB_RANGE) || DEFAULT_MAX_KB

  def max_bytes = max_kb.kilobytes

  def max_side = settings["max_side"].to_i.presence_in(SIDE_RANGE) || DEFAULT_MAX_SIDE

  # Whether uploads over the limits are made lighter as they arrive. On
  # unless the site says otherwise.
  def optimize_uploads? = settings["optimize_uploads"] != false

  # "750 KB", "1.5 MB".
  def max_size_label = max_kb >= 1000 ? "#{(max_kb / 1000.0).round(1).to_s.delete_suffix(".0")} MB" : "#{max_kb} KB"

  # From Settings › Media's form; values out of range fall back to the defaults.
  def update(attrs)
    kb = attrs["max_kb"].to_i
    side = attrs["max_side"].to_i
    Setting.set(KEY, "max_kb" => kb.presence_in(KB_RANGE) || DEFAULT_MAX_KB,
      "max_side" => side.presence_in(SIDE_RANGE) || DEFAULT_MAX_SIDE,
      "optimize_uploads" => ActiveModel::Type::Boolean.new.cast(attrs["optimize_uploads"]) == true)
  end
end
