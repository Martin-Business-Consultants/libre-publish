# frozen_string_literal: true

source "https://rubygems.org"

# Every gem is held to the major version it's tested at (to the minor for
# 0.x), so `bundle update` can't take one across a breaking release unseen.

gem "authentication-zero", "~> 4.0"
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", "~> 1.25", require: false
gem "commonmarker", "~> 2.10"
gem "csv", "~> 3.3"
gem "fugit", "~> 1.13"
gem "herb", "~> 0.11.0"
gem "image_processing", "~> 1.2"
gem "importmap-rails", "~> 2.2"
gem "jbuilder", "~> 2.15"
gem "kamal", "~> 2.12", require: false, group: [:development, :deploy]
gem "lexxy", "~> 0.9.33"
gem "propshaft", "~> 1.3"
gem "rails-active_search", "~> 0.1"
gem "puma", "~> 8.0"
gem "rails", "~> 8.1.3"
gem "reactionview", "~> 0.6.0"
gem "rubyzip", "~> 3.0"
gem "solid_cable", "~> 4.0"
gem "solid_cache", "~> 1.0"
gem "solid_queue", "~> 1.7"
gem "sqlite3", "~> 2.9"
gem "stimulus-rails", "~> 1.3"
gem "thruster", "~> 0.1.26", require: false
gem "turbo-rails", "~> 2.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Plugins (docs/plugins.md): installed ones live in plugins/, one gem each,
# put there by `bin/rails "plugins:install[git url]"` (the defaults, Forms
# and Media, among them).
Dir.glob(File.expand_path("plugins/*/*.gemspec", __dir__)).sort.each do |gemspec|
  gem File.basename(gemspec, ".gemspec"), path: File.dirname(gemspec)
end

# The website's theme (themes/*, docs/themes.md): an engine that draws the
# public site, so the CMS serves it itself. At most one.
Dir.glob(File.expand_path("themes/*/*.gemspec", __dir__)).sort.each do |gemspec|
  gem File.basename(gemspec, ".gemspec"), path: File.dirname(gemspec)
end

# The reference plugin (engines/hello), for working on the core and its
# specs: no install carries it.
group :development, :test do
  Dir.glob(File.expand_path("engines/*/*.gemspec", __dir__)).sort.each do |gemspec|
    gem File.basename(gemspec, ".gemspec"), path: File.dirname(gemspec)
  end
end

group :development, :test do
  gem "brakeman", "~> 8.1", require: false
  gem "bundler-audit", "~> 0.9.3", require: false
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "factory_bot_rails", "~> 6.5"
  gem "rspec-rails", "~> 8.0"
  gem "rubocop-rails-omakase", "~> 1.1", require: false
end

group :development do
  gem "web-console", "~> 4.3"
  gem "letter_opener", "~> 1.10"
end

group :test do
  gem "capybara", "~> 3.40"
  gem "capybara-lockstep", "~> 2.3"
  gem "selenium-webdriver", "~> 4.48"
end
