# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings › Themes › Customize", type: :request do
  let(:admin) { create(:user) }

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views"), design: [
      {name: "accent", label: "Accent color", type: "color", default: "#a8382f"},
      {name: "heading_font", label: "Headings", type: "select", default: "serif",
       options: {"serif" => "Georgia, serif", "sans" => "system-ui, sans-serif"}},
      {name: "show_banner", label: "Show the banner", type: "boolean", default: true},
      {name: "tagline", label: "Tagline", type: "string", default: "Grow well"}
    ]
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  before { sign_in_as admin }

  it "offers the theme's settings, keeps what's chosen held to each type, and resets" do
    get settings_themes_path
    expect(response.body).to include(edit_settings_theme_design_path("fixture"))

    get edit_settings_theme_design_path("fixture")
    expect(response.body).to include("Accent color", %(value="#a8382f"), "Show the banner")

    patch settings_theme_design_path("fixture"),
      params: {design: {accent: "#1D4ED8", heading_font: "sans", show_banner: "0", tagline: "  ", evil: "x"}}
    expect(Website::Design.values).to eq("accent" => "#1d4ed8", "heading_font" => "sans", "show_banner" => false, "tagline" => "Grow well")
    expect(Website::Design.css).to eq(":root { --design-accent: #1d4ed8; --design-heading-font: system-ui, sans-serif; --design-tagline: Grow well; }")

    patch settings_theme_design_path("fixture"), params: {design: {accent: "red; } body { display:none", heading_font: "comic"}}
    expect(Website::Design.values).to include("accent" => "#a8382f", "heading_font" => "serif")

    delete settings_theme_design_path("fixture")
    expect(Website::Design.values["accent"]).to eq("#a8382f")
  end

  it "puts the settings on the website, and a change refreshes its cache" do
    before = Website.cache_version
    travel 1.second do
      Website::Design.update(Website.theme, accent: "#000000")
    end

    expect(Website.cache_version).not_to eq(before)
    expect(ApplicationController.helpers.website_design(:accent)).to eq("#000000")
    expect(ApplicationController.helpers.website_design_tags).to include("--design-accent: #000000;")
  end

  it "needs settings:write to change it" do
    editor = create(:user, admin: false, role: create(:role, permissions: %w[settings:read]))
    sign_in_as editor

    patch settings_theme_design_path("fixture"), params: {design: {accent: "#000000"}}

    expect(Website::Design.values["accent"]).to eq("#a8382f")
  end
end
