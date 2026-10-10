# frozen_string_literal: true

require "rails_helper"

# The delivery API (/api/v1): what a site builds from. Live content only,
# whatever the token; one answer shape; a cursor for incremental reads.
RSpec.describe "Delivery API v1", type: :request do
  let(:admin) { create(:user) }
  let(:token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  def json = JSON.parse(response.body)

  def page(slug, **attrs) = Page.create!({slug: slug, title: slug.titleize, status: "published", locale: "en"}.merge(attrs))

  before { BlockType.create!(slug: "text", label: "Text", fields: [{"name" => "body", "type" => "markdown", "label" => "Body"}]) }

  it "answers lists in one shape, paged, live content only — even to a token that could see drafts" do
    page("about", blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "Hi"}}])
    page("draft", status: "draft")

    get "/api/v1/pages", headers: token, params: {per: 1}

    expect(json.keys).to include("data", "meta")
    expect(json["data"].map { it["path"] }).to eq(["about"])
    expect(json["meta"]).to eq("page" => 1, "per" => 1, "total" => 1, "next_page" => nil)
    expect(json["data"].first["blocks"].first.dig("data", "body")).to eq("Hi")
    expect(response.headers["Cache-Tag"]).to eq("pages,page:about")

    get "/api/v1/pages/draft", headers: token
    expect(response).to have_http_status(:not_found)
  end

  it "never lists a draft entry in a collection_list, and tags the page with the collection it lists" do
    BlockType.create!(slug: "collection_list", label: "Collection list", fields: [{"name" => "collection_slug", "type" => "string", "label" => "Collection"}, {"name" => "filter_status", "type" => "string", "label" => "Status"}])
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    posts.entries.create!(slug: "out", title: "Out", status: "published", published_at: 1.day.ago, locale: "en")
    posts.entries.create!(slug: "wip", title: "WIP", status: "draft", locale: "en")
    page("blog", blocks: [{"type" => "collection_list", "data" => {"collection_slug" => "posts", "filter_status" => "any"}}])

    get "/api/v1/pages/blog", headers: token

    resolved = json.dig("data", "blocks", 0, "resolved")
    expect(resolved["entries"].map { it["slug"] }).to eq(%w[out])
    expect(resolved["entries"].first).to include("url" => "/posts/out", "collection" => "posts")
    expect(response.headers["Cache-Tag"]).to eq("page:blog,collection:posts")
  end

  it "reads a nested page by its path, with its translations" do
    group = TranslationGroup.create!(kind: "page")
    parent = page("company", translation_group: nil)
    page("team", parent: parent, translation_group: group)
    page("equipe", locale: "fr", translation_group: group)

    get "/api/v1/pages/company/team", headers: token

    expect(json.dig("data", "path")).to eq("company/team")
    expect(json.dig("data", "translations").map { it["locale"] }).to eq(["fr"])
  end

  it "gives everything once, then only what changed and what stopped being live" do
    about = page("about")
    gone = page("gone")
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    collection.entries.create!(slug: "hello", title: "Hello", status: "published")
    Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

    get "/api/v1/content", headers: token
    expect(json["meta"]["full"]).to be(true)
    expect(json.dig("data", "pages").map { it["path"] }).to contain_exactly("about", "gone")
    expect(json.dig("data", "entries").map { it["slug"] }).to eq(["hello"])
    expect(json.dig("data", "globals").map { it["slug"] }).to eq(["footer"])
    cursor = json["meta"]["cursor"]

    travel 1.minute do
      about.update!(title: "About us")
      gone.update!(status: "draft")

      get "/api/v1/content", headers: token, params: {since: cursor}
    end

    expect(json["meta"]["full"]).to be(false)
    expect(json.dig("data", "pages").map { it["title"] }).to eq(["About us"])
    expect(json.dig("data", "entries")).to be_empty
    expect(json.dig("data", "removed", "pages")).to eq([{"id" => gone.id, "path" => "gone"}])
  end

  it "starts over when the cursor is older than the trash keeps things" do
    page("about")

    get "/api/v1/content", headers: token, params: {since: 40.days.ago.iso8601}

    expect(json["meta"]["full"]).to be(true)
    expect(json.dig("data", "pages").size).to eq(1)
  end

  it "describes the site and its locales" do
    Setting.set("general", title: "Acme", site_base_url: "https://acme.test", default_locale: "en")
    page("about")
    page("a-propos", locale: "fr")

    get "/api/v1/site", headers: token

    expect(json["data"]).to include("name" => "Acme", "url" => "https://acme.test", "default_locale" => "en", "locales" => %w[en fr])
    expect(json.dig("meta", "api_version")).to eq("v1")
    expect(json.dig("meta", "cms_url")).to match(%r{\Ahttps?://[^/]+\z})
  end

  it "publishes JSON Schema for block types, collections, globals and SEO, with the CMS's types" do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "cover", "type" => "asset", "label" => "Cover"}]})

    get "/api/v1/schema", headers: token

    body = json.dig("data", "block_types", "text", "data", "properties", "body")
    expect(body).to include("type" => "string", "x-cms-type" => "markdown", "title" => "Body")
    expect(json.dig("data", "collections", "posts", "frontmatter", "properties", "cover", "x-cms-type")).to eq("asset")
    expect(json.dig("data", "seo", "properties")).to have_key("meta_title")
  end

  it "serves redirects as JSON, and as a Cloudflare _redirects file, exact rules first" do
    Redirect.create!(source_path: "/blog/*", destination_url: "/news/*", status_code: 301)
    Redirect.create!(source_path: "/old", destination_url: "/new", status_code: 302)

    get "/api/v1/redirects", headers: token
    expect(json["data"].map { it["source"] }).to eq(["/old", "/blog/*"])

    get "/api/v1/redirects.txt", headers: token
    expect(response.media_type).to eq("text/plain")
    expect(response.body.lines.map(&:strip)).to eq(["/old /new 302", "/blog/* /news/:splat 301"])
  end

  it "lists sitemap URLs on the public site, and Site health's checks to build against" do
    Setting.set("general", site_base_url: "https://acme.test")
    page("about")

    get "/api/v1/sitemap", headers: token
    expect(json["data"].map { it["url"] }).to include("https://acme.test/about")

    get "/api/v1/site_health", headers: token
    expect(json["data"].first.keys).to include("key", "title", "ok", "state", "for_site")
    expect(json["data"].find { it["key"] == "privacy_page" }["for_site"]).to be(true)
    expect(json["data"].find { it["key"] == "recent_backup" }["for_site"]).to be(false)
    expect(json["meta"]).to include("total", "passing")
  end

  it "needs a token that can read" do
    get "/api/v1/pages"
    expect(response).to have_http_status(:unauthorized)
  end
end
