# frozen_string_literal: true

# The core's deprecations (Cms.deprecator) report as Rails' own do: logged in
# development, printed in a test run (a plugin's suite included), kept quiet
# in production. After initializing, once lib/ autoloads.
Rails.application.config.after_initialize do
  Rails.application.deprecators[:cms] = Cms.deprecator
end
