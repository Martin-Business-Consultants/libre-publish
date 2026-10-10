# frozen_string_literal: true

require_relative "bundled_ruby" # A release updated in place runs on the Ruby it carries.

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# On a release's own Ruby (config/bundled_ruby.rb) its standard library comes
# in through RUBYLIB, which Ruby searches ahead of the gems Bundler adds, so a
# default gem's older copy there would beat the bundle's. Put the standard
# library back behind the gems, where Ruby keeps it.
if ENV["CMS_BUNDLED_RUBY"]
  rubylib = ENV["RUBYLIB"].to_s.split(":")
  $LOAD_PATH.replace(($LOAD_PATH - rubylib) + ($LOAD_PATH & rubylib))
end

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
