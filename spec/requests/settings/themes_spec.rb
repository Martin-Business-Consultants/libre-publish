# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings › Themes", type: :request do
  let(:admin) { create(:user) }

  around do |example|
    registered = Website.theme
    Cms::Plugins.register(:fixture, name: "Fixture", version: "1.0.0", description: "The test theme.", enabled_by_default: true)
    Website.register :fixture, name: "Fixture", version: "1.0.0", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
    forget_plugin(:fixture)
  end

  it "lists the themes apart from the plugins, with which one draws the site and an update that's out" do
    allow(InstalledPlugins).to receive(:repo).and_call_original
    allow(InstalledPlugins).to receive(:repo).with("fixture").and_return("acme/fixture-theme")
    allow(UpdateCheck::Plugins).to receive(:latest_version).and_return(nil)
    allow(UpdateCheck::Plugins).to receive(:latest_version).with("fixture").and_return("1.1.0")
    sign_in_as admin

    get settings_themes_path
    expect(response.body).to include("Fixture", "acme/fixture-theme", "1.1.0 available", "Active", "Or any theme")
    expect(response.body).to include(%(href="#{settings_themes_path}"))

    get settings_plugins_path
    expect(response.body).not_to include("The test theme.")
  end

  it "comes back here after installing one from it" do
    sign_in_as admin

    post settings_plugins_installations_path(from: "themes"), params: {repo: "acme/fixture-theme"}

    expect(response).to redirect_to(settings_themes_path)
  end

  it "draws the site with the theme that's switched on, when two are registered" do
    others = Website.themes.except("fixture")
    others.each_key { Website.themes.delete(it) } # themes a checkout has linked
    Cms::Plugins.register(:other, name: "Other", version: "1.0.0", description: "x", enabled_by_default: true)
    Website.register :other, name: "Other", version: "1.0.0", views: Rails.root.join("spec/fixtures/website_theme/views")
    expect(Website.theme.key).to eq("other")

    switch_plugin :other, on: false
    expect(Website.theme.key).to eq("fixture")
    expect(Website).to be_enabled
  ensure
    Website.themes.delete("other")
    Website.themes.merge!(others) if others
    forget_plugin(:other)
  end
end
