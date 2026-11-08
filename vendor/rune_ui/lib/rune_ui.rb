require "active_support"
require "active_support/core_ext/module/attribute_accessors"
require "rune_ui/version"
require "rune_ui/icons"
require "rune_ui/helper"
require "rune_ui/engine"

# A no-build UI kit after Rune: an app shell (sidebar, panel, ⌘K palette), components as view
# helpers, plain CSS in the `rune` cascade layer, and Stimulus controllers named rune-*.
#
# An app tells it two things, in config/initializers/rune_ui.rb:
#
#   RuneUi.register_icons(runs: '<circle cx="8" cy="8" r="5.5"/>')  # 16×16 stroke paths
#   RuneUi.badge_tones.merge!("completed" => :ok, "failed" => :danger) # its statuses → tones
module RuneUi
  # Badge tones (see marks.css): neutral, ok, danger, attention, accent, busy (accent, pulsing),
  # outline (no fill).
  TONES = %i[neutral ok danger attention accent busy outline].freeze

  # A status or word → tone, for #badge. Anything not listed shows neutral.
  mattr_accessor :badge_tones, default: {}

  # The stylesheets, in order. Each is in a layer of `rune` (declared in tokens.css), so an
  # app's own, unlayered CSS always wins. lexxy.css is unlayered: it overrides Lexxy's own.
  STYLESHEETS = %w[tokens base shell layout marks buttons forms cards lists settings flash palette prose composer overlays data].freeze

  def self.icons = Icons::ALL

  def self.register_icons(**paths)
    Icons::ALL.merge!(paths.transform_keys(&:to_sym))
  end

  def self.tone_for(status)
    tone = badge_tones[status.to_s] || badge_tones[status.to_s.to_sym] || status.to_s
    TONES.include?(tone.to_sym) ? tone.to_sym : :neutral
  end
end
