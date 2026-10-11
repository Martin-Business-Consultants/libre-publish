# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# shadcn-html (vendor/shadcn-html/README.md): its theme and component
# stylesheets, at theme/… and components/<name>/<name>.css.
Rails.application.config.assets.paths << Rails.root.join("vendor/shadcn-html")
