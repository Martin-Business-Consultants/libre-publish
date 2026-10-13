# frozen_string_literal: true

require "rails_helper"

# robots.txt on the Sitemap screen: made from Settings › Search plus extra
# rules, or written by hand; checked for what's likely wrong; published on
# this host (with a theme) and to a frontend's build (GET /api/v1/robots).
RSpec.describe "robots.txt", type: :request do
  let(:admin) { create(:user) }
  let(:editor) { create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write])) }
  let(:site) { ServiceToken.issue(name: "Site", role: create(:role, permissions: Permissions::SITE_DEFAULT), created_by: nil) }

  before { Setting.set("general", "site_base_url" => "https://greenthumb.test") }

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  it "shows what the site publishes, with what's likely wrong, and saves extra rules or a whole file" do
    sign_in_as admin
    get sitemap_path
    expect(response.body).to include(sitemap_robots_path)

    get sitemap_robots_path
    expect(response.body).to include("What the site publishes", "Sitemap: https://greenthumb.test/sitemap.xml", "Nothing looks wrong")

    patch sitemap_robots_path, params: {robots: {robots_mode: "generated", robots_extra: "User-agent: *\r\nDisallow: /thank-you"}}
    expect(SearchSettings.get["robots_extra"]).to eq("User-agent: *\nDisallow: /thank-you")
    get sitemap_robots_path
    expect(response.body).to include("Disallow: /thank-you")

    patch sitemap_robots_path, params: {robots: {robots_mode: "custom", robots_custom: "User-agent: *\nDisallow: /\nNonsense here"}}
    expect(SearchSettings).to be_custom_robots
    get sitemap_robots_path
    expect(response.body).to include("keeps the whole site out of search", "isn&#39;t a rule crawlers know", "doesn&#39;t say where the sitemap is", "Use the made one again")

    patch sitemap_robots_path, params: {robots: {robots_mode: "custom"}, reset: "1"}
    expect(SearchSettings).not_to be_custom_robots
  end

  it "takes settings:write to change it" do
    sign_in_as editor
    get sitemap_robots_path
    expect(response).to have_http_status(:ok)
    patch sitemap_robots_path, params: {robots: {robots_mode: "custom", robots_custom: "User-agent: *\nDisallow: /"}}
    expect(SearchSettings).not_to be_custom_robots
  end

  it "publishes the written one on this host, and the headless host stays closed" do
    SearchSettings.update_robots(robots_mode: "custom", robots_custom: "User-agent: *\nDisallow: /private\n\nSitemap: https://greenthumb.test/sitemap.xml")
    get "/robots.txt"
    expect(response.body).to eq("User-agent: *\nDisallow: /private\n\nSitemap: https://greenthumb.test/sitemap.xml\n")

    Setting.set("general", "serving" => "api_only")
    get "/robots.txt"
    expect(response.body).to eq("User-agent: *\nDisallow: /\n")
  end

  it "gives a frontend's build the site's robots.txt, without this host's admin lines" do
    Setting.set("general", "serving" => "api_only")
    headers = {"Authorization" => "Bearer #{site.token}"}

    get "/api/v1/robots", headers: headers
    expect(response.parsed_body["data"]).to include("mode" => "generated")
    expect(response.parsed_body.dig("data", "text")).to include("Allow: /", "Sitemap: https://greenthumb.test/sitemap.xml")
    expect(response.parsed_body.dig("data", "text")).not_to include("/cms/", "/api/")

    SearchSettings.update_robots(robots_mode: "custom", robots_custom: "User-agent: *\nAllow: /")
    get "/api/v1/robots.txt", headers: headers
    expect(response.body).to eq("User-agent: *\nAllow: /\n")
  end

  it "rebuilds the site when it changes" do
    sign_in_as admin
    allow(Deploys).to receive(:schedule_later)
    patch sitemap_robots_path, params: {robots: {robots_mode: "generated", robots_extra: ""}}
    expect(Deploys).to have_received(:schedule_later).with(reason: "settings.robots_updated")
    expect(Deploys::Change.from("settings.robots_updated", nil)).to include("tags" => ["robots"])
  end
end
