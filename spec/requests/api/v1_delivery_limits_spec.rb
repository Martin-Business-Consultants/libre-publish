# frozen_string_literal: true

require "rails_helper"

# What keeps the delivery API cheap to read: conditional GET, a cached
# /content body for as long as nothing it's built from changes
# (DeliveryVersion), and a per-token rate limit.
RSpec.describe "Delivery API v1 caching and limits", type: :request do
  let(:admin) { create(:user) }
  let(:token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  def json = JSON.parse(response.body)

  def page(slug, **attrs) = Page.create!({slug: slug, title: slug.titleize, status: "published", locale: "en"}.merge(attrs))

  around do |example|
    caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    example.run
  ensure
    ActionController::Base.perform_caching = caching
  end

  it "answers 304 to a reader that already has the answer, until something changes" do
    page("about")
    get "/api/v1/content", headers: token
    etag = response.headers["ETag"]

    get "/api/v1/content", headers: token.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty

    page("team")
    get "/api/v1/content", headers: token.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "pages").map { it["path"] }).to eq(%w[about team])

    get "/api/v1/globals", headers: token
    get "/api/v1/globals", headers: token.merge("If-None-Match" => response.headers["ETag"])
    expect(response).to have_http_status(:not_modified)
  end

  it "serves /content's data from the cache until something it's built from changes, byte for byte" do
    page("about")
    get "/api/v1/content", headers: token
    first = json

    expect_any_instance_of(Page).not_to receive(:expanded_blocks)
    get "/api/v1/content", headers: token
    expect(json["data"]).to eq(first["data"])

    RSpec::Mocks.space.reset_all
    Page.find_by!(slug: "about").update!(title: "Our story")
    get "/api/v1/content", headers: token
    expect(json.dig("data", "pages", 0, "title")).to eq("Our story")
  end

  it "renders the same body cached as uncached" do
    page("about")
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    posts.entries.create!(slug: "hello", title: "Hello & welcome", status: "published", published_at: 1.day.ago, locale: "en")

    ActionController::Base.perform_caching = false
    get "/api/v1/content", headers: token
    uncached = json["data"]

    ActionController::Base.perform_caching = true
    2.times { get "/api/v1/content", headers: token }
    expect(json["data"]).to eq(uncached)
  end

  it "moves the version for an edit, an insert, a trash and a settings change" do
    about = page("about")
    versions = [DeliveryVersion.current]

    about.update!(title: "Our story")
    versions << DeliveryVersion.current
    page("team")
    versions << DeliveryVersion.current
    about.trash
    versions << DeliveryVersion.current
    Setting.set("general", {"default_locale" => "fr"})
    versions << DeliveryVersion.current

    expect(versions.uniq.size).to eq(versions.size)
  end

  it "moves the version for an edit even when another row's time is later" do
    page("imported", updated_at: 1.year.from_now)
    about = page("about")
    before = DeliveryVersion.current

    about.update!(title: "Our story")

    expect(DeliveryVersion.current).not_to eq(before)
  end

  it "limits each token, not everyone, and says when to come back" do
    other = create(:user)
    Rails.cache.write("rate-limit:api/v1:ApiToken:#{admin.api_token.id}", Api::V1::BaseController::RATE_LIMIT, raw: true)

    get "/api/v1/site", headers: token

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("60")
    expect(json["error"]).to eq("rate_limited")

    get "/api/v1/site", headers: {"Authorization" => "Bearer #{other.api_token.token}"}
    expect(response).to have_http_status(:ok)
  end
end
