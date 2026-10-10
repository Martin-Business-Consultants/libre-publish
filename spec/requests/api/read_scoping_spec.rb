# frozen_string_literal: true

require "rails_helper"

# What a token reads through the API's lookups — search, references and the
# delivery snapshot: only the kinds its role reads, and of pages and entries
# only the live ones unless it can write them. The site's own read-only
# token never sees a draft's title, slug or text.
RSpec.describe "API reads, scoped to the token", type: :request do
  def auth(capabilities)
    {"Authorization" => "Bearer #{create(:user, admin: false, role: create(:role, permissions: capabilities)).api_token.token}"}
  end

  def json = JSON.parse(response.body)

  let(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  before do
    Page.create!(slug: "pricing", title: "Pricing", status: "published", locale: "en")
    Page.create!(slug: "pricing-next", title: "Pricing next", status: "draft", locale: "en")
    posts.entries.create!(slug: "pricing-live", title: "Pricing live", status: "published", locale: "en")
    posts.entries.create!(slug: "pricing-wip", title: "Pricing wip", status: "draft", locale: "en")
  end

  describe "search" do
    it "refuses a token that reads no pages" do
      post "/api/search", params: {q: "pricing"}, headers: auth(%w[assets:read]), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "finds only live records for a token that can't write them, and no entries without entries:read" do
      post "/api/search", params: {q: "pricing"}, headers: auth(%w[pages:read]), as: :json

      expect(response).to have_http_status(:ok)
      expect(json["pages"].map { it["slug"] }).to eq(%w[pricing])
      expect(json["entries"]).to eq([])

      post "/api/search", params: {q: "pricing"}, headers: auth(%w[pages:read entries:read]), as: :json
      expect(json["entries"].map { it["slug"] }).to eq(%w[pricing-live])
    end

    it "finds drafts for a token that writes them" do
      post "/api/search", params: {q: "pricing"}, headers: auth(%w[pages:read pages:write entries:read entries:write]), as: :json

      expect(json["pages"].map { it["slug"] }).to contain_exactly("pricing", "pricing-next")
      expect(json["entries"].map { it["slug"] }).to contain_exactly("pricing-live", "pricing-wip")
    end
  end

  describe "references" do
    before do
      Page.find_each { ContentReference.create!(owner: it, ref_type: "asset", ref_id: "7", kind: "image", position: 0) }
      posts.entries.find_each { ContentReference.create!(owner: it, ref_type: "asset", ref_id: "7", kind: "image", position: 0) }
      footer = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})
      ContentReference.create!(owner: footer, ref_type: "asset", ref_id: "7", kind: "image", position: 0)
    end

    it "refuses a token that reads no pages" do
      get "/api/references", params: {ref_type: "asset", ref_id: "7"}, headers: auth(%w[assets:read])

      expect(response).to have_http_status(:forbidden)
    end

    it "lists only the live owners of the kinds the token reads, and counts only those" do
      get "/api/references", params: {ref_type: "asset", ref_id: "7"}, headers: auth(%w[pages:read])

      expect(json["owners"].map { it["slug"] }).to eq(%w[pricing])
      expect(json.dig("pagination", "total")).to eq(1)

      get "/api/references", params: {ref_type: "asset", ref_id: "7"}, headers: auth(%w[pages:read entries:read globals:read])
      expect(json["owners"].map { it["slug"] }).to contain_exactly("pricing", "pricing-live", "footer")
    end

    it "lists drafts to a token that writes them" do
      get "/api/references", params: {ref_type: "asset", ref_id: "7"}, headers: auth(%w[pages:read pages:write entries:read entries:write])

      expect(json["owners"].map { it["slug"] }).to contain_exactly("pricing", "pricing-next", "pricing-live", "pricing-wip")
    end
  end

  describe "the delivery snapshot" do
    before { Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {}) }

    it "sends entries and globals only to a token that reads them" do
      get "/api/v1/content", headers: auth(%w[pages:read])

      expect(json.dig("data", "pages").map { it["path"] }).to eq(%w[pricing])
      expect(json.dig("data", "entries")).to eq([])
      expect(json.dig("data", "globals")).to eq([])

      get "/api/v1/content", headers: auth(%w[pages:read entries:read globals:read])
      expect(json.dig("data", "entries").map { it["slug"] }).to eq(%w[pricing-live])
      expect(json.dig("data", "globals").map { it["slug"] }).to eq(%w[footer])
    end

    it "doesn't serve a pages-only token the cached answer of a token that reads everything" do
      caching = ActionController::Base.perform_caching
      ActionController::Base.perform_caching = true

      get "/api/v1/content", headers: auth(%w[pages:read entries:read globals:read])
      expect(json.dig("data", "entries")).not_to be_empty

      get "/api/v1/content", headers: auth(%w[pages:read])
      expect(json.dig("data", "entries")).to eq([])
      expect(json.dig("data", "globals")).to eq([])
    ensure
      ActionController::Base.perform_caching = caching
    end
  end
end
