# frozen_string_literal: true

require "rails_helper"

# Feeds, IndexNow and the SEO audit.
RSpec.describe "Growing in search", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }
  let(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  before do
    BlockType::Defaults.install!
    Setting.set("general", {"title" => "Green Thumb", "site_base_url" => "https://greenthumb.example.com"})
  end

  around do |example|
    Rails.configuration.x.indexnow = nil
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Rails.configuration.x.indexnow = false
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  it "serves a drawn collection's newest entries as RSS, linked from every page" do
    posts.entries.create!(slug: "raised-beds", title: "Raised beds", status: "published", locale: "en",
      published_at: Time.utc(2026, 4, 2), seo: {"meta_description" => "Why we build them."})
    posts.entries.create!(slug: "draft", title: "Draft", status: "draft", locale: "en")
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en")

    get "/posts/feed.xml"
    feed = Nokogiri::XML(response.body)
    expect(response.media_type).to eq("application/rss+xml")
    expect(feed.css("item title").map(&:text)).to eq(["Raised beds"])
    expect(feed.at("item link").text).to eq("https://greenthumb.example.com/posts/raised-beds")
    expect(feed.at("item description").text).to eq("Why we build them.")

    get "/"
    expect(response.body).to include(%(type="application/rss+xml" title="Posts" href="https://greenthumb.example.com/posts/feed.xml"))

    get "/people/feed.xml"
    expect(response).to have_http_status(:not_found)
  end

  it "tells IndexNow about a published page, with a key the site serves" do
    requests = []
    allow(Net::HTTP).to receive(:start).and_wrap_original { |_original, *_args, **_kw, &block|
      http = Object.new
      http.define_singleton_method(:post) { |path, body, headers| requests << [path, JSON.parse(body)]; Net::HTTPOK.new("1.1", "200", "OK") }
      block.call(http)
    }

    perform_enqueued_jobs do
      Page.create!(slug: "services", title: "Services", status: "published", locale: "en")
    end

    key = SearchSettings.get["indexnow_key"]
    expect(requests.last&.last).to include("host" => "greenthumb.example.com", "key" => key,
      "urlList" => ["https://greenthumb.example.com/services"])

    get "/#{key}.txt"
    expect(response.body).to eq(key)
  end

  it "says nothing to IndexNow for a site on a private address, or when it's switched off" do
    Setting.set("general", {"site_base_url" => "http://localhost:3000"})
    expect(IndexNow).not_to be_enabled

    Setting.set("general", {"site_base_url" => "https://greenthumb.example.com"})
    SearchSettings.update(indexnow: "0")
    expect(IndexNow).not_to be_enabled
  end

  it "lists what to fix across the site, and a page's own in its SEO tab" do
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en",
      blocks: [{"type" => "text", "version" => 1, "data" => {"body" => "See [our services](/services) and [old](/gone)."}}])
    Page.create!(slug: "services", title: "Home", status: "published", locale: "en", seo: {"meta_description" => "Short."})
    sign_in_as admin

    get tools_seo_audit_path
    expect(response.body).to include("No meta description", "Links to /gone", "Shares its title with", "is 6 characters")
    expect(response.body).not_to include("Links to /services")

    get edit_page_path("home")
    expect(response.body).to include("SEO checks", "Links to /gone")
  end
end
