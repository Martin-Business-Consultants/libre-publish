# frozen_string_literal: true

require "rails_helper"

# What search engines and AI readers get from the website: robots.txt,
# llms.txt and each page's Markdown, and every page's <head>.
RSpec.describe "The website for search and AI", type: :request do
  let(:posts) do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "summary", "label" => "Summary", "type" => "string"}]})
  end

  before do
    BlockType::Defaults.install!
    Setting.set("general", {"title" => "Green Thumb", "description" => "Gardens, planted well.", "site_base_url" => "https://greenthumb.test",
      "phone" => "555-0100", "address_line1" => "1 Elm St", "city" => "Asheville", "state" => "NC", "zip" => "28801"})
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en",
      blocks: [{"type" => "text", "version" => 1, "data" => {"body" => "Welcome **in**"}}])
    services = Page.create!(slug: "services", title: "Services", status: "published", locale: "en",
      seo: {"meta_description" => "What we do.", "og_title" => "Our services", "nofollow" => true},
      blocks: [{"type" => "heading", "version" => 1, "data" => {"level" => "2", "text" => "Planting"}},
               {"type" => "text", "version" => 1, "data" => {"body" => "Beds and **borders**."}}])
    Page.create!(slug: "fall", title: "Fall planting", status: "published", locale: "en", parent: services)
    Page.create!(slug: "secret", title: "Secret", status: "published", locale: "en", seo: {"noindex" => true})
    posts.entries.create!(slug: "raised-beds", title: "Raised beds", status: "published", locale: "en",
      body_markdown: "Better drainage.", published_at: Time.utc(2026, 4, 2), frontmatter: {"summary" => "Why"})
  end

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  it "lets an editor choose the AI crawlers and who the site is in Settings › Search" do
    sign_in_as create(:user)

    get settings_search_path
    expect(response.body).to include("AI answer engines", "AI model training", "Profiles elsewhere")

    patch settings_search_path, params: {search: {ai_search: "allow", ai_training: "block", organization: "Person", same_as: "https://x.test/me"}}
    expect(SearchSettings.get).to include("ai_training" => "block", "organization" => "Person", "same_as" => ["https://x.test/me"])
  end

  describe "robots.txt" do
    it "keeps the admin and API out, names the sitemap, and lets AI crawlers in by default" do
      get "/robots.txt"

      expect(response.body).to include("User-agent: *", "Disallow: /cms/", "Disallow: /api/", "Sitemap: https://greenthumb.test/sitemap.xml")
      expect(response.body).not_to include("GPTBot")
    end

    it "blocks AI training and AI answer engines separately, as Settings › Search says" do
      SearchSettings.update(ai_search: "allow", ai_training: "block", robots_extra: "User-agent: SlowBot\nCrawl-delay: 10")
      get "/robots.txt"
      expect(response.body).to include("User-agent: GPTBot\nUser-agent: ClaudeBot", "User-agent: Google-Extended", "User-agent: SlowBot")
      expect(response.body).not_to include("OAI-SearchBot")

      SearchSettings.update(ai_search: "block", ai_training: "allow")
      get "/robots.txt"
      expect(response.body).to include("User-agent: OAI-SearchBot", "User-agent: PerplexityBot")
      expect(response.body).not_to include("GPTBot")
    end
  end

  it "closes a headless install's host to every crawler" do
    Website.theme = nil

    get "/robots.txt"

    expect(response.body).to eq("User-agent: *\nDisallow: /\n")
  end

  it "names each page's translations in the sitemap" do
    group = TranslationGroup.create!(kind: "page")
    Page.find_by!(slug: "services").update!(translation_group: group)
    Page.create!(slug: "servicios", title: "Servicios", status: "published", locale: "es", translation_group: group)

    get "/sitemap.xml"

    expect(response.body).to include('xmlns:xhtml="http://www.w3.org/1999/xhtml"', 'hreflang="es"', 'hreflang="en"')
  end

  describe "for AI readers" do
    it "lists the site's pages and entries in llms.txt, each linking to its Markdown" do
      get "/llms.txt"

      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to start_with("# Green Thumb\n\n> Gardens, planted well.")
      expect(response.body).to include("## Pages", "- [Services](https://greenthumb.test/services.md): What we do.",
        "- [Home](https://greenthumb.test/index.md)", "## Posts", "- [Raised beds](https://greenthumb.test/posts/raised-beds.md)")
      expect(response.body).not_to include("Secret")
    end

    it "serves each page and entry as Markdown, and none hidden from search" do
      get "/services.md"
      expect(response.body).to start_with("# Services\n\n> What we do.\n\n## Planting\n\nBeds and **borders**.")
      expect(response.body).to include("Source: https://greenthumb.test/services")

      get "/index.md"
      expect(response.body).to include("# Home", "Welcome **in**")

      get "/posts/raised-beds.md"
      expect(response.body).to include("# Raised beds", "Better drainage.")

      get "/secret.md"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a page's <head>" do
    def head_of(path)
      get path
      Nokogiri::HTML(response.body)
    end

    def json_ld(doc) = doc.css("script[type='application/ld+json']").map { JSON.parse(it.text) }

    it "has its overrides, robots, the Markdown link, and structured data made from the content" do
      doc = head_of("/services/fall")

      expect(doc.at("meta[name=robots]")["content"]).to eq("index, follow, max-image-preview:large, max-snippet:-1")
      expect(doc.at("link[rel=alternate][type='text/markdown']")["href"]).to eq("https://greenthumb.test/services/fall.md")
      graph = json_ld(doc).first["@graph"]
      expect(graph.map { it["@type"] }).to eq(%w[Organization WebSite WebPage BreadcrumbList])
      expect(graph.last["itemListElement"].map { it["name"] }).to eq(["Home", "Services", "Fall planting"])

      services = head_of("/services")
      expect(services.at("meta[property='og:title']")["content"]).to eq("Our services")
      expect(services.at("meta[name=robots]")["content"]).to start_with("index, nofollow")
    end

    it "describes an entry as an article, a local business with its address, and links its translations" do
      SearchSettings.update(organization: "LocalBusiness", same_as: "https://www.instagram.com/greenthumb not-a-url")
      doc = head_of("/posts/raised-beds")

      expect(doc.at("meta[property='og:type']")["content"]).to eq("article")
      expect(doc.at("meta[property='article:published_time']")["content"]).to start_with("2026-04-02")
      organization, _site, article = json_ld(doc).first["@graph"]
      expect(organization).to include("@type" => "LocalBusiness", "name" => "Green Thumb", "telephone" => "555-0100",
        "sameAs" => ["https://www.instagram.com/greenthumb"], "address" => include("addressLocality" => "Asheville"))
      expect(article).to include("@type" => "Article", "headline" => "Raised beds", "datePublished" => start_with("2026-04-02"))

      # The headline is the entry's title, not its SEO title for results.
      posts.entries.find_by!(slug: "raised-beds").update!(seo: {"meta_title" => "Raised beds | Green Thumb"})
      article = json_ld(head_of("/posts/raised-beds")).first["@graph"].find { it["@type"] == "Article" }
      expect(article["headline"]).to eq("Raised beds")

      secret = head_of("/secret")
      expect(secret.at("meta[name=robots]")["content"]).to eq("noindex, follow")
      expect(secret.at("link[type='text/markdown']")).to be_nil
    end
  end

  describe "one address" do
    it "sends www. to the site's own address, and leaves other hosts be" do
      host! "www.greenthumb.test"
      get "/services?x=1"
      expect(response).to redirect_to("https://greenthumb.test/services?x=1")
      expect(response).to have_http_status(:moved_permanently)

      host! "cms.example.net"
      get "/services"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "an entry's Markdown" do
    it "carries its own fields, and leaves a block's settings out" do
      posts.update!(schema: {"fields" => [{"name" => "summary", "label" => "Summary", "type" => "string"},
        {"name" => "layout", "label" => "Layout", "type" => "select", "options" => %w[wide narrow]}]})
      posts.entries.find_by!(slug: "raised-beds").update!(frontmatter: {"summary" => "Why we build them", "layout" => "wide"})

      get "/posts/raised-beds.md"

      expect(response.body).to include("**Summary:** Why we build them")
      expect(response.body).not_to include("wide")
    end
  end
end
