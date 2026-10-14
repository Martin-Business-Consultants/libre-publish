# frozen_string_literal: true

require "rails_helper"

RSpec.describe Website, ".theme" do
  around do |example|
    registered = Website.theme
    themes = Website.themes.dup
    example.run
  ensure
    Website.themes.replace(themes)
    Website.theme = registered
  end

  def register(key)
    Cms::Plugins.register key, name: key.to_s.titleize, version: "0.1.0", description: "A theme.", enabled_by_default: true
    Website.register key, name: key.to_s.titleize, version: "0.1.0", views: Rails.root.join("tmp")
  end

  before do
    Website.themes.clear
    register :chosen_one
    register :newcomer # registered last, and on by default
  end

  it "draws with the theme switched on in Settings, not one only on by default" do
    Cms::Plugins.switch!(:chosen_one, on: true)

    expect(Website.theme.key).to eq("chosen_one")
  end

  it "draws with the last registered when none was switched on" do
    expect(Website.theme.key).to eq("newcomer")
  end

  it "draws with another when the last registered is switched off" do
    Cms::Plugins.switch!(:newcomer, on: false)

    expect(Website.theme.key).to eq("chosen_one")
  end
end
