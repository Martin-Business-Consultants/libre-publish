require_relative "lib/rune_ui/version"

Gem::Specification.new do |spec|
  spec.name = "rune_ui"
  spec.version = RuneUi::VERSION
  spec.authors = [ "Ted Martin" ]
  spec.summary = "A no-build UI kit for Rails: components, plain CSS and Stimulus controllers."
  spec.description = "View helpers and partials (buttons, menus, cards, lists, forms, settings, an app shell with " \
                     "sidebar and ⌘K palette), light/dark plain CSS in a cascade layer, and Stimulus controllers " \
                     "served through importmap. For Hotwire apps on Propshaft."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["{app,config,lib}/**/*", "README.md", "LICENSE.md"]

  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "actionview", ">= 7.1"
  spec.add_dependency "importmap-rails", ">= 2.0"
  spec.add_dependency "stimulus-rails", ">= 1.3"
end
