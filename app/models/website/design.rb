# frozen_string_literal: true

# A theme's design settings: its colors, fonts and the few choices it lets an
# editor make without touching code (WordPress's Customizer), declared when
# it registers and changed in Settings › Themes › Customize. Kept in the
# "website_design" setting, by theme.
#
#   Website.register :acme, …, design: [
#     {name: "accent", label: "Accent color", type: "color", default: "#a8382f"},
#     {name: "heading_font", label: "Headings", type: "select", default: "serif",
#      options: {"serif" => "Georgia, serif", "sans" => "system-ui, sans-serif"}},
#     {name: "show_announcement", label: "Show the announcement bar", type: "boolean", default: true}
#   ]
#
#   website_design(:accent)   # "#a8382f", or what an editor chose (WebsiteHelper)
#   website_design_tags       # <style>:root { --design-accent: #a8382f; … }</style>
module Website::Design
  SETTING_KEY = "website_design"
  TYPES = %w[color select boolean string].freeze
  COLOR = /\A#\h{6}\z/

  Setting = Data.define(:name, :label, :type, :default, :options, :help) do
    def self.from(hash)
      hash = hash.to_h.transform_keys(&:to_sym)
      new(name: hash.fetch(:name).to_s, label: hash[:label] || hash[:name].to_s.humanize, type: (hash[:type] || "string").to_s,
        default: hash[:default], options: hash[:options].to_h.transform_keys(&:to_s), help: hash[:help])
    end

    # A value as it's kept: a color is #rrggbb, a choice one of its options,
    # a switch true or false; anything else falls back to the default.
    def cast(value)
      case type
      when "color" then value.to_s.downcase.match?(COLOR) ? value.to_s.downcase : default
      when "select" then options.key?(value.to_s) ? value.to_s : default
      when "boolean" then ActiveModel::Type::Boolean.new.cast(value) || false
      else value.to_s.strip.presence || default
      end
    end

    # What a CSS custom property holds: a choice's value (a font stack), a
    # color as it is. Switches have none.
    def css(value)
      case type
      when "select" then options[value.to_s]
      when "boolean" then nil
      else value
      end
    end
  end

  module_function

  def values(theme = Website.theme)
    return {} unless theme

    chosen = ::Setting.get(SETTING_KEY)[theme.key].to_h
    theme.settings.to_h { [it.name, chosen.key?(it.name) ? it.cast(chosen[it.name]) : it.default] }
  end

  def value(name, theme = Website.theme) = values(theme)[name.to_s]

  # Saves what an editor chose, held to each setting's type.
  def update(theme, submitted)
    submitted = submitted.to_h.stringify_keys
    kept = theme.settings.to_h { [it.name, it.cast(submitted[it.name])] }
    ::Setting.set(SETTING_KEY, {theme.key => kept})
  end

  def reset(theme) = ::Setting.unset(SETTING_KEY, theme.key)

  # The CSS custom properties, --design-<name>, for every setting that has one.
  def css(theme = Website.theme)
    return "" unless theme

    values = values(theme)
    properties = theme.settings.filter_map do |setting|
      value = setting.css(values[setting.name])
      "--design-#{setting.name.dasherize}: #{value.to_s.gsub(/[;{}<>]/, "")};" if value.present?
    end
    properties.any? ? ":root { #{properties.join(" ")} }" : ""
  end

  # Changes with the settings, for the website's cache.
  def version = ::Setting.find_by(key: SETTING_KEY)&.updated_at&.to_i
end
