# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
# The admin falls back to the server's zone when Settings › General names
# none (Site.server_time_zone); pin it so specs don't depend on the machine.
ENV["TZ"] ||= "UTC"

require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "capybara/rspec"
require "selenium-webdriver"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
# db/schema.rb is the core's: an installed plugin's tables (plugins/, not
# committed) come from its own migrations, run on top of it.
ActiveRecord::Base.connection_pool.then do |pool|
  context = ActiveRecord::MigrationContext.new(Rails.application.config.paths["db/migrate"].to_a, pool.schema_migration, pool.internal_metadata)
  ActiveRecord::Migration.suppress_messages { context.migrate } if context.needs_migration?
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  # Every example starts from an empty database. bin/ci seeds the test
  # database after the suite runs ("Tests: Seeds"), so clear whatever a
  # previous run left behind before this one starts.
  config.before(:suite) { ActiveRecord::Tasks::DatabaseTasks.truncate_all }
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
  end

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  # A spec that travels in time comes back, whatever included the helpers
  # (a spec file including them at the top level skips their own teardown).
  config.after { travel_back }
  config.include AuthenticationHelpers, type: ->(type, _metadata) { [:system, :request, :controller].include?(type) }
end
