# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cms::Hooks do
  after { %i[alpha beta].each { forget_plugin(it) } }

  def register(key)
    Cms::Plugins.register(key, name: key.to_s.titleize, version: "0.1.0", description: "A test plugin.", enabled_by_default: true)
  end

  describe "filters" do
    it "hands the value through each plugin's filter, lowest priority first, with the context" do
      register :alpha
      register :beta
      Cms::Plugins.filter(:alpha, "test.title", priority: 20) { |title, suffix:| "#{title}#{suffix}" }
      Cms::Plugins.filter(:beta, "test.title", priority: 5) { |title, **| title.upcase }

      expect(described_class.apply("test.title", "home", suffix: " | Acme")).to eq("HOME | Acme")
    end

    it "skips a plugin that's off, and one whose filter raises" do
      register :alpha
      register :beta
      switch_plugin :beta, on: false
      Cms::Plugins.filter(:alpha, "test.title") { |*| raise "boom" }
      Cms::Plugins.filter(:beta, "test.title") { |*| "off" }
      allow(Rails.error).to receive(:report)

      expect(described_class.apply("test.title", "home")).to eq("home")
      expect(Rails.error).to have_received(:report).with(an_instance_of(RuntimeError), hash_including(context: {plugin: :alpha, hook: "test.title"}))
    end

    it "drops a plugin's hooks when it registers again, as on a code reload" do
      register :alpha
      Cms::Plugins.filter(:alpha, "test.title") { |title, **| "#{title}!" }
      register :alpha

      expect(described_class.apply("test.title", "home")).to eq("home")
    end
  end

  describe "actions" do
    it "runs on every <event>.cms notification while its plugin is on" do
      register :alpha
      heard = []
      Cms::Plugins.on(:alpha, "page.published") { |payload| heard << payload[:event] }

      ActiveSupport::Notifications.instrument("page.published.cms", event: "page.published", data: {})
      described_class.run("page.published", event: "again")
      switch_plugin :alpha, on: false
      described_class.run("page.published", event: "while off")

      expect(heard).to eq(%w[page.published again])
    end
  end
end
