# frozen_string_literal: true

# A plugin's update strategy for a spec (Cms::Plugins.update_strategy): a
# runner class that deploys, registered under `via` by a plugin that's on,
# and forgotten afterwards with the plugin.
module UpdateStrategyHelpers
  def register_update_strategy(via, configured: true, redeploys: true)
    runner = Class.new do
      class << self
        attr_accessor :started, :configured, :redeploys
      end

      def self.label = "Deployer"
      def self.description = "A deploy through the deployer"
      def self.configured? = configured
      def self.redeploys? = redeploys
      def self.unavailable_reason = nil

      def initialize(upgrade)
        @upgrade = upgrade
      end

      def start = self.class.started = true
      def check = nil
      def timing_out_since = @upgrade.created_at
      def where_to_look = "The deployer says."
    end
    runner.configured = configured
    runner.redeploys = redeploys

    Cms::Plugins.register :deployer, name: "Deployer", version: "0.1.0", description: "Deploys.", enabled_by_default: true
    Cms::Plugins.update_strategy :deployer, via, -> { runner }
    runner
  end
end

RSpec.configure do |config|
  config.include UpdateStrategyHelpers
  config.after { forget_plugin(:deployer) }
end
