# frozen_string_literal: true

# The site's visual identity (Settings › Branding), stored under
# Setting["branding"]: logo, favicon, colors, font, corners, shadow, and a
# top bar that's dark whatever the appearance.
#
# The public site reads the raw setting. The admin reads it through here:
# `stylesheet` turns all of it — color, type and surface — into the theming
# tokens Runwell UI is drawn from (ui/theme.css), served as /branding.css, and only ever
# from values that passed the checks below: the setting is written by admins,
# but it still ends up inside CSS.
class Branding
  KEY = "branding"

  PERMITTED = %i[logo_id favicon_id primary_color secondary_color font border_radius box_shadow top_bar].freeze

  FONTS = {
    "Inter"            => "Inter — Clean modern sans",
    "DM Sans"          => "DM Sans — Geometric",
    "Manrope"          => "Manrope — Soft sans",
    "Playfair Display" => "Playfair Display — Editorial serif",
    "Lora"             => "Lora — Calligraphic serif"
  }.freeze

  # The admin's top bar: as the appearance draws everything, or dark in
  # either (.admin-bar--dark, which takes the dark tokens, _global.css).
  TOP_BARS = {"match" => "Match the appearance", "dark" => "Dark"}.freeze

  RADII   = %w[none small medium large].freeze
  SHADOWS = %w[none small medium large].freeze

  HEX = /\A#(\h{3}|\h{6})\z/

  FALLBACK_STACK = %(-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif)

  def self.current
    new(Setting.get(KEY))
  end

  # Overwrites rather than merges, so a field cleared in the form is cleared
  # (Setting.set deep-merges).
  def self.save(attrs)
    record = Setting.find_or_initialize_by(key: KEY)
    data = attrs.to_h.stringify_keys.slice(*PERMITTED.map(&:to_s))
    data["logo_id"] = data["logo_id"].presence
    data["favicon_id"] = data["favicon_id"].presence
    record.data = data.compact_blank
    record.save!
    record
  end

  def initialize(data)
    @data = (data || {}).to_h.stringify_keys
  end

  def [](key) = @data[key.to_s]

  def primary_color
    color = @data["primary_color"].to_s.strip
    color if color.match?(HEX)
  end

  def secondary_color
    color = @data["secondary_color"].to_s.strip
    color if color.match?(HEX)
  end

  def font
    @data["font"].presence_in(FONTS.keys)
  end

  def border_radius
    @data["border_radius"].presence_in(RADII)
  end

  def box_shadow
    @data["box_shadow"].presence_in(SHADOWS)
  end

  def dark_top_bar? = @data["top_bar"] == "dark"

  # What every mail client draws; anything else (WebP, a large file) goes as
  # a PNG of it, and an SVG, which few draw and can't be converted, not at all.
  EMAIL_IMAGE_TYPES = %w[image/png image/jpeg image/gif].freeze
  EMAIL_LOGO_BYTES = 200.kilobytes

  # The logo as an email carries it (ApplicationMailer#email_logo_src):
  # {filename:, mime_type:, content:}, or nil without one a mail client can
  # show.
  def email_logo
    file = @data["logo_id"].presence && Asset.with_attached_file.find_by(id: @data["logo_id"])&.file
    return unless file&.attached?

    if file.content_type.in?(EMAIL_IMAGE_TYPES) && file.byte_size <= EMAIL_LOGO_BYTES
      {filename: file.filename.to_s, mime_type: file.content_type, content: file.download}
    elsif file.variable?
      png = file.variant(resize_to_limit: [600, 240], format: :png).processed
      {filename: "#{file.filename.base}.png", mime_type: "image/png", content: png.download}
    end
  rescue ActiveStorage::Error, SystemCallError, LoadError
    nil
  end

  def google_font_url
    "https://fonts.googleapis.com/css2?family=#{ERB::Util.url_encode(font)}:wght@400;500;600;700&display=swap" if font
  end

  # The visual identity as the delivery API gives a site (/api/v1/site's
  # `branding`): only what's set and valid, the logo and favicon as assets
  # (Asset::Delivery) when the media library has them.
  def delivered
    {
      "logo" => MediaLibrary.find(@data["logo_id"])&.delivery,
      "favicon" => MediaLibrary.find(@data["favicon_id"])&.delivery,
      "primary_color" => primary_color, "secondary_color" => secondary_color,
      "font" => font, "border_radius" => border_radius, "box_shadow" => box_shadow
    }.compact
  end

  def customized?
    [primary_color, secondary_color, font, border_radius, box_shadow].any?(&:present?)
  end

  # The admin is drawn with Runwell UI (app/assets/stylesheets/ui), whose
  # components read shadcn's tokens (ui/tokens.css), built from theming tokens
  # (ui/theme.css). The branding sets those theming tokens, as Runwell's
  # Appearance does: the primary color is the accent (an OKLCH triple, lifted
  # for the dark theme, with dark words on it when white wouldn't read), the
  # secondary color tints the ink steps with its hue, faintly, the font is
  # --font-sans, the corners --radius-scale and --radius-control, the shadow
  # the --shadow-xs…lg steps controls, cards, menus and dialogs use.

  # The ink steps' lightness in the light and dark theme (ui/theme.css), and
  # how much of the secondary color's chroma each takes (capped, so text
  # stays text).
  INK_STEPS = {
    "darkest" => [14.1, 98.5, 0.5],
    "darker" => [37, 87.1, 0.4],
    "dark" => [55.2, 70.5, 0.35],
    "medium" => [64, 55.2, 0.3],
    "light" => [87.1, 37, 0.15],
    "lighter" => [92, 27.4, 0.1],
    "lightest" => [96.7, 21, 0.06]
  }.freeze
  INK_CHROMA_CAP = 0.04

  # The accent's paler steps (selection), light and dark theme: lightness,
  # and the share of the accent's chroma they keep.
  ACCENT_STEPS = {
    "light" => [84, 42, 0.4],
    "lighter" => [93, 30, 0.18],
    "lightest" => [97, 24, 0.08]
  }.freeze

  # Corners: a multiple of shadcn's 0.625rem for containers (cards, menus,
  # dialogs), and the one radius every control shares.
  CORNERS = {
    "none" => {scale: "0", control: "0"},
    "small" => {scale: "0.5", control: "0.25rem"},
    "medium" => {scale: "1", control: "0.5rem"},
    "large" => {scale: "1.6", control: "0.75rem"}
  }.freeze

  # Shadow: the steps shadcn's components use (shadow-xs on controls, -sm on
  # cards, -md on menus, -lg on dialogs), softer, as they are, or deeper.
  SHADOW_TOKENS = {
    "none" => {xs: "0 0 #0000", sm: "0 0 #0000", md: "0 0 #0000", lg: "0 0 #0000"},
    "small" => {
      xs: "0 1px 1px 0 rgb(0 0 0 / 0.03)",
      sm: "0 1px 2px 0 rgb(0 0 0 / 0.05)",
      md: "0 2px 6px -1px rgb(0 0 0 / 0.08)",
      lg: "0 4px 12px -2px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.06)"
    },
    "medium" => {
      xs: "0 1px 2px 0 rgb(0 0 0 / 0.05)",
      sm: "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)",
      md: "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)",
      lg: "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)"
    },
    "large" => {
      xs: "0 1px 3px 0 rgb(0 0 0 / 0.08)",
      sm: "0 4px 8px -2px rgb(0 0 0 / 0.12), 0 2px 4px -2px rgb(0 0 0 / 0.08)",
      md: "0 10px 15px -3px rgb(0 0 0 / 0.12), 0 4px 6px -4px rgb(0 0 0 / 0.1)",
      lg: "0 25px 50px -12px rgb(0 0 0 / 0.25), 0 8px 16px -8px rgb(0 0 0 / 0.15)"
    }
  }.freeze

  def stylesheet
    light = []
    dark = []

    if (color = primary_color)
      lightness, chroma, hue = oklch(color)
      light << "--lch-accent: #{triple(lightness, chroma, hue)};"
      ACCENT_STEPS.each { |step, (paler, _, share)| light << "--lch-accent-#{step}: #{triple(paler, chroma * share, hue)};" }
      light << "--lch-ink-inverted: var(--lch-black);" if light?(color)
      dark << "--lch-accent: #{triple([lightness, 70].max, [chroma, 0.16].min, hue)};"
      ACCENT_STEPS.each { |step, (_, darker, share)| dark << "--lch-accent-#{step}: #{triple(darker, chroma * share, hue)};" }
    end

    if (color = secondary_color)
      _, chroma, hue = oklch(color)
      INK_STEPS.each do |step, (light_lightness, dark_lightness, share)|
        tint = [chroma * share, INK_CHROMA_CAP].min
        light << "--lch-ink-#{step}: #{triple(light_lightness, tint, hue)};"
        dark << "--lch-ink-#{step}: #{triple(dark_lightness, tint, hue)};"
      end
    end

    light << %(--font-sans: "#{font}", #{FALLBACK_STACK};) if font
    if (corners = CORNERS[border_radius])
      light << "--radius-scale: #{corners[:scale]};" << "--radius-control: #{corners[:control]};"
    end
    SHADOW_TOKENS.fetch(box_shadow, {}).each { |step, value| light << "--shadow-#{step}: #{value};" }

    css = +""
    css << ":root {\n  #{light.join("\n  ")}\n}\n" if light.any?
    if dark.any?
      # The dark theme's own selectors (ui/theme.css), so these win there.
      css << %(html[data-theme="dark"] {\n  #{dark.join("\n  ")}\n}\n)
      css << %(@media (prefers-color-scheme: dark) {\n  html:not([data-theme]) {\n    #{dark.join("\n    ")}\n  }\n}\n)
    end
    css
  end

  private

  def triple(lightness, chroma, hue)
    "#{lightness.round(1)}% #{chroma.round(3)} #{hue.round(1)}"
  end

  # A hex color as OKLCH: [lightness (0–100), chroma, hue in degrees], by
  # Björn Ottosson's OKLab matrices from linear sRGB.
  def oklch(hex)
    red, green, blue = linear_rgb(hex)
    long = Math.cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    medium = Math.cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    short = Math.cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    lightness = 0.2104542553 * long + 0.7936177850 * medium - 0.0040720468 * short
    a = 1.9779984951 * long - 2.4285922050 * medium + 0.4505937099 * short
    b = 0.0259040371 * long + 0.7827717662 * medium - 0.8086757660 * short
    chroma = Math.sqrt(a**2 + b**2)
    hue = (chroma < 0.0001) ? 0.0 : Math.atan2(b, a) * 180 / Math::PI % 360
    [lightness * 100, chroma, hue]
  end

  def linear_rgb(hex)
    digits = hex.delete_prefix("#")
    digits = digits.chars.map { it * 2 }.join if digits.size == 3
    digits.scan(/../).map { it.to_i(16) / 255.0 }.map { (it <= 0.04045) ? it / 12.92 : ((it + 0.055) / 1.055)**2.4 }
  end

  # Whether a hex color is light enough that dark text reads better on it than
  # white (relative luminance, WCAG's, above 0.45).
  def light?(hex)
    red, green, blue = linear_rgb(hex)
    0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.45
  end
end
