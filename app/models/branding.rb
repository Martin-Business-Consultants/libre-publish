# frozen_string_literal: true

# The site's visual identity (Settings › Branding), stored under
# Setting["branding"]: logo, favicon, colors, font, corners, shadow, and a
# top bar that's dark whatever the appearance.
#
# The public site reads the raw setting. The admin reads it through here:
# `stylesheet` turns all of it — color, type and surface — into overrides of
# shadcn-html's tokens (vendor/shadcn-html, _global.css), served as /branding.css, and only ever
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
  # either (shadcn-html's .dark on the bar, which takes the dark tokens).
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

  def customized?
    [primary_color, secondary_color, font, border_radius, box_shadow].any?(&:present?)
  end

  # Words on a primary fill: near-black on a light color, near-white on a
  # dark one (shadcn-html's foregrounds).
  ON_LIGHT = "oklch(0.205 0 0)"
  ON_DARK = "oklch(0.985 0 0)"

  # How strongly the secondary color tints the neutral surfaces, mixed into
  # whichever background the appearance has.
  TINTED = {secondary: 10, muted: 8, accent: 10, sidebar: 4, "sidebar-accent": 10}.freeze

  # Corners: shadcn-html's --radius and the steps around it, which its
  # components and the utilities' rounded-sm/-md/-lg/-xl read (badges,
  # controls, notices, cards and menus). Each step is given, so "none" never
  # works out a negative one.
  CORNERS = {
    "none" => {sm: "0", md: "0", lg: "0", xl: "0"},
    "small" => {sm: "0.125rem", md: "0.1875rem", lg: "0.25rem", xl: "0.375rem"},
    "medium" => {sm: "0.25rem", md: "0.375rem", lg: "0.5rem", xl: "0.75rem"},
    "large" => {sm: "0.375rem", md: "0.625rem", lg: "0.875rem", xl: "1.25rem"}
  }.freeze

  # Shadow: a card's (shadow-surface) and what floats over the page
  # (shadow-overlay: menus, dialogs, sheets, toasts).
  SHADOW_TOKENS = {
    "none" => {surface: "0 0 #0000", overlay: "0 0 #0000"},
    "small" => {
      surface: "0 1px 2px 0 rgb(0 0 0 / 0.05)",
      overlay: "0 4px 12px -2px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.06)"
    },
    "medium" => {
      surface: "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)",
      overlay: "0 0 0 1px rgb(0 0 0 / 0.04), 0 10px 16px rgb(0 0 0 / 0.08), 0 2px 6px rgb(0 0 0 / 0.12)"
    },
    "large" => {
      surface: "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)",
      overlay: "0 25px 50px -12px rgb(0 0 0 / 0.25), 0 8px 16px -8px rgb(0 0 0 / 0.15)"
    }
  }.freeze

  def stylesheet
    declarations = []
    if (color = primary_color)
      on = light?(color) ? ON_LIGHT : ON_DARK
      declarations << "--primary: #{color};" << "--primary-foreground: #{on};" << "--ring: #{color};"
      declarations << "--sidebar-primary: #{color};" << "--sidebar-primary-foreground: #{on};"
    end
    if (color = secondary_color)
      TINTED.each { |token, percent| declarations << "--#{token}: color-mix(in oklch, #{color} #{percent}%, var(--background));" }
    end
    declarations << %(--font-sans: "#{font}", #{FALLBACK_STACK};) if font
    if (corners = CORNERS[border_radius])
      declarations << "--radius: #{corners[:lg]};"
      corners.each { |size, value| declarations << "--radius-#{size}: #{value};" }
    end
    SHADOW_TOKENS.fetch(box_shadow, {}).each { |kind, value| declarations << "--shadow-#{kind}: #{value};" }

    # On .dark too: shadcn-html's dark theme sets these there, and the dark
    # admin bar (.admin-bar.dark) is a .dark of its own.
    declarations.any? ? ":root,\n.dark {\n  #{declarations.join("\n  ")}\n}\n" : ""
  end

  private

  # Whether a hex color is light enough that dark text reads better on it than
  # white (relative luminance, WCAG's, above 0.45).
  def light?(hex)
    digits = hex.delete_prefix("#")
    digits = digits.chars.map { it * 2 }.join if digits.size == 3
    red, green, blue = digits.scan(/../).map { it.to_i(16) / 255.0 }.map { it <= 0.03928 ? it / 12.92 : ((it + 0.055) / 1.055)**2.4 }
    0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.45
  end
end
