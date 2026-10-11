# frozen_string_literal: true

require "rails_helper"

# How the site is served (Serving, Settings › General): the theme's website by
# default, with the delivery API off; the website with chosen content as JSON
# too; or headless, the API alone.
RSpec.describe "How the site is served", type: :request do
  let(:admin) { create(:user) }
  let(:site) { ServiceToken.issue(name: "Site", role: create(:role, permissions: Permissions::SITE_DEFAULT), created_by: nil) }
  let(:token) { {"Authorization" => "Bearer #{site.token}"} }
  let!(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }
  let!(:events) { Collection.create!(slug: "events", name: "Events", schema: {"fields" => []}) }

  before do
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en")
    posts.entries.create!(slug: "hello", title: "Hello", status: "published", locale: "en")
    events.entries.create!(slug: "fair", title: "Fair", status: "published", locale: "en")
  end

  describe "Website, the default" do
    it "has the delivery API and the frontend's endpoints off" do
      expect(Serving.mode).to eq("website")

      get "/api/v1/pages", headers: token
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["message"]).to include("Settings › General")

      get "/api/v1/pages"
      expect(response).to have_http_status(:unauthorized)

      get "/api/frontend", headers: token
      expect(response).to have_http_status(:not_found)
      get "/frontend/install.sh"
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the management API and the form submissions on" do
      get "/api/pages", headers: {"Authorization" => "Bearer #{admin.api_token.token}"}
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Website + API" do
    before { serve_over_api("website_api", pages: false) }

    it "serves only what's chosen: each collection that says so, the pages (and globals) all or none" do
      posts.update!(api_enabled: true)

      get "/api/v1/collections/posts/entries", headers: token
      expect(response).to have_http_status(:ok)
      get "/api/v1/collections/events/entries", headers: token
      expect(response).to have_http_status(:not_found)

      get "/api/v1/collections", headers: token
      expect(response.body).to include("posts")
      expect(response.body).not_to include("events")

      get "/api/v1/pages", headers: token
      expect(response).to have_http_status(:not_found)
      get "/api/v1/content", headers: token
      expect(response.body).to include("hello")
      expect(response.body).not_to include("fair", %("title":"Home"))

      serve_over_api("website_api", pages: true)
      get "/api/v1/pages", headers: token
      expect(response).to have_http_status(:ok)
    end
  end

  describe "API only" do
    before { serve_over_api("api_only") }

    it "serves everything over the API, and shows a blank page at the CMS's own address" do
      get "/api/v1/collections/events/entries", headers: token
      expect(response).to have_http_status(:ok)

      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<meta name="robots" content="noindex, nofollow">))
      expect(response.body).not_to include("/cms")

      get "/robots.txt"
      expect(response.body).to include("Disallow: /")
      get "/sitemap.xml"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Settings › General" do
    before { sign_in_as admin }

    it "chooses the mode and what's served, and warns which machines read the API lately" do
      site.update_column(:last_used_at, 2.days.ago)

      get settings_general_path
      expect(response.body).to include("How the site is served", "Website + API", "API only")
      expect(response.body).to include("These machine tokens read the site in the last 30 days", "Site")

      patch settings_general_path, params: {settings: {serving: "website_api", api_pages: "1", api_collections: ["", "events"]}}
      expect(Serving.mode).to eq("website_api")
      expect(Serving.pages?).to be(true)
      expect(events.reload.api_enabled?).to be(true)
      expect(posts.reload.api_enabled?).to be(false)

      patch settings_general_path, params: {settings: {serving: "nonsense"}}
      expect(Serving.mode).to eq("website_api")
    end

    it "shows a page's JSON tab only while it's served over the API" do
      page = Page.find_by!(slug: "home")
      get edit_page_path(page.path)
      expect(response.body).not_to include(%(data-tab="json"))

      serve_over_api("website_api", pages: true)
      get edit_page_path(page.path)
      expect(response.body).to include(%(data-tab="json"))
    end
  end
end
