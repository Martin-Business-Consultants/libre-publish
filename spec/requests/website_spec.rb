# frozen_string_literal: true

require "rails_helper"

# The website, drawn by a theme (here spec/fixtures/website_theme), at the
# addresses the CMS gives its pages and entries.
RSpec.describe "Website", type: :request do
  before { BlockType::Defaults.install! }

  let!(:home) { Page.create!(slug: "home", title: "Home", status: "published", locale: "en", blocks: [text_block("Welcome **in**")]) }
  let(:posts) do
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "summary", "label" => "Summary", "type" => "string"}]})
  end

  def text_block(body) = {"type" => "text", "version" => 1, "data" => {"body" => body}}

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
  end

  # The page and its sitemap are cached for everyone: what they print about
  # their own address can't come from a header the requester chose.
  it "prints its own address from the install's settings, whatever Host or X-Forwarded-Host a request sends" do
    get "/", headers: {"Host" => "evil.test", "X-Forwarded-Host" => "evil.test"}
    expect(response.body).not_to include("evil.test")
    expect(response.body).to include(%(<link rel="canonical" href="http://example.com/"))

    get "/sitemap.xml", headers: {"X-Forwarded-Host" => "evil.test"}
    expect(response.body).not_to include("evil.test")
  end

  it "draws the home page at /, from its blocks" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1>Home</h1>", "Welcome <strong>in</strong>")
  end

  it "draws an entry with its collection's template, and nothing for a collection the theme doesn't draw" do
    posts.entries.create!(slug: "hello", title: "Hello", status: "published", locale: "en", frontmatter: {"summary" => "A first post"})
    Collection.create!(slug: "people", name: "People", schema: {"fields" => []}).entries.create!(slug: "ann", title: "Ann", status: "published", locale: "en")

    get "/posts/hello"
    expect(response.body).to include("<h1>Hello</h1>", "A first post")

    get "/people/ann"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Not here")
  end

  it "answers an unknown address with the theme's 404, after Tools › Redirects" do
    Redirect.create!(source_path: "/old", destination_url: "/", status_code: 301)

    get "/old"
    expect(response).to redirect_to("/")
    expect(response).to have_http_status(:moved_permanently)

    get "/nowhere"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Not here", %(content="noindex, nofollow"))
  end

  it "gives every page one address" do
    Page.create!(slug: "about", title: "About", status: "published", locale: "en")

    get "/about/?ref=nav"

    expect(response).to redirect_to("/about?ref=nav")
    expect(response).to have_http_status(:moved_permanently)
  end

  it "leaves the admin, the API and plugins their own paths" do
    # As in production: no detailed exception pages, so the API answers its own 404.
    allow(Rails.application).to receive(:env_config).and_return(Rails.application.env_config.merge("action_dispatch.show_detailed_exceptions" => false))

    get "/cms/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Not here")

    get "/sign_in"
    expect(response).to redirect_to("/cms/sign_in")

    get "/api/no-such-thing"
    expect(response.media_type).to eq("application/json")
  end

  it "shows a draft only in an editor's preview, never cached" do
    Page.create!(slug: "soon", title: "Coming soon", status: "draft", locale: "en")

    get "/soon", params: {preview: ""}
    expect(response).to have_http_status(:not_found)

    sign_in_as create(:user)
    get "/soon", params: {preview: ""}
    expect(response.body).to include("Coming soon")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
  end

  it "lets anyone cache a published page until the content changes" do
    get "/"
    etag = response.headers["ETag"]
    expect(response.headers["Cache-Control"]).to include("public")

    get "/", headers: {"If-None-Match" => etag}
    expect(response).to have_http_status(:not_modified)

    home.update!(title: "Welcome home")
    get "/", headers: {"If-None-Match" => etag}
    expect(response).to have_http_status(:ok)
  end

  it "fails a template that reads a field its block type doesn't declare" do
    BlockType.create!(slug: "misread", label: "Misread", category: "Content", version: 1, fields: [{"name" => "heading", "label" => "Heading", "type" => "string"}])
    home.update_columns(blocks: [{"type" => "misread", "version" => 1, "data" => {"heading" => "Hi"}}])

    expect { get "/" }.to raise_error(ActionView::Template::Error) { |error|
      expect(error.cause).to be_a(Website::Fields::Unknown)
      expect(error.message).to include('misread has no field "headline" (it has heading)')
    }
  end

  it "serves the theme's web app manifest, and none for a theme without one" do
    get "/site.webmanifest"
    expect(response.media_type).to eq("application/manifest+json")
    expect(JSON.parse(response.body)).to eq("name" => "Fixture")

    Website.register :bare, name: "Bare", version: "1", views: Rails.root.join("spec/fixtures/website_theme/none")
    get "/site.webmanifest"
    expect(response).to have_http_status(:not_found)
  end

  context "without a theme" do
    around do |example|
      Website.theme = nil
      example.run
    end

    it "sends / to the admin, at /cms" do
      get "/"

      expect(response).to redirect_to("/cms")
    end
  end

  # The "scripts" global (analytics, a chat widget): each item's head in
  # <head>, its body before </body>, as pasted.
  it "puts the scripts global's items in the head and at the end of the body" do
    SiteSetup.new(name: "Acme", owner_email: "owner@example.com").call if Global.find_by(slug: "scripts").nil?
    Global.find_by!(slug: "scripts").update!(data: {"items" => [
      {"name" => "GA4", "head" => %(<script async src="https://www.googletagmanager.com/gtag/js?id=G-TEST"></script>), "body" => ""},
      {"name" => "Chat", "head" => "", "body" => "<script>window.chat = true</script>"},
      {"name" => "Old pixel", "head" => "<script>window.pixel = true</script>", "enabled" => false}
    ]})

    get "/"

    expect(response).to have_http_status(:ok)
    head, body = response.body.split("</head>", 2)
    expect(head).to include("googletagmanager.com/gtag/js?id=G-TEST")
    expect(body).to include("<script>window.chat = true</script></body>")
    expect(response.body).not_to include("window.pixel")
  end

  describe "plugins' filters" do
    before { Cms::Plugins.register(:seo_plus, name: "SEO+", version: "1", description: "x", enabled_by_default: true) }
    after { forget_plugin(:seo_plus) }

    it "change a page's title tag, its blocks, and add to its head and body" do
      Cms::Plugins.filter(:seo_plus, "website.seo") { |seo, record:| seo.merge(title: "#{record.title} | Acme") }
      Cms::Plugins.filter(:seo_plus, "website.block") { |html, block:| html + tag.hr(class: block["type"]) }
      Cms::Plugins.filter(:seo_plus, "website.head") { |html, **| html + tag.meta(name: "generator", content: "Libre Publish") }
      Cms::Plugins.filter(:seo_plus, "website.body") { |*| "<script>alert(1)</script>" }

      get "/"

      expect(response.body).to include("<title>Home | Acme</title>", %(<hr class="text">), %(<meta name="generator" content="Libre Publish">))
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end
  end

  def tag = ActionController::Base.helpers.tag
end
