# frozen_string_literal: true

# The core's specs run headless, as an install without a theme does, though
# a theme in themes/ is loaded in this bundle. A spec tagged `website: true`
# gets the theme the app registered (Website.theme) back.
RSpec.configure do |config|
  config.around do |example|
    registered = Website.theme
    Website.theme = (registered if example.metadata[:website])
    example.run
  ensure
    Website.theme = registered
  end
end
