require "rune_ui/helpers/icons"
require "rune_ui/helpers/marks"
require "rune_ui/helpers/components"
require "rune_ui/helpers/rich_text"
require "rune_ui/helpers/shell"
require "rune_ui/helpers/overlays"

module RuneUi
  # Everything a view can call. Included in ActionController::Base's helpers, before an app's
  # own, so the app can override any of it.
  module Helper
    include Helpers::Icons
    include Helpers::Marks
    include Helpers::Components
    include Helpers::RichText
    include Helpers::Shell
    include Helpers::Overlays
  end
end
