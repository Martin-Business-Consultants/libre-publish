require "rails/engine"

module RuneUi
  class Engine < ::Rails::Engine
    # Stylesheets (app/assets/stylesheets/rune_ui) are on the asset path as an engine's
    # app/assets always are; the controllers in app/javascript need adding.
    initializer "rune_ui.assets" do |app|
      app.config.assets.paths << root.join("app/javascript") if app.config.respond_to?(:assets)
    end

    initializer "rune_ui.importmap", before: "importmap" do |app|
      next unless app.config.respond_to?(:importmap)

      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    # Through the controller's helpers, so an app's own helper of the same name wins (an app
    # overrides #page_title_in_bar?, say).
    initializer "rune_ui.helpers" do
      ActiveSupport.on_load(:action_controller_base) { helper RuneUi::Helper }
    end
  end
end
