# frozen_string_literal: true

# The site spec/contracts/delivery_contract_spec.rb answers from: the one the
# Go core seeds for its contract (librepublishgo internal/cms/contract_test.go,
# recorded in spec/fixtures/contracts/go), made in this CMS — the starter
# block types, a collection with most field types and one with blocks, live
# and draft pages and entries, a synced pattern, an image, a global,
# redirects, the branding — plus keys left over from older data, which
# mustn't be delivered.
module GoContractSite
  POSTS_FIELDS = [
    {"name" => "summary", "label" => "Summary", "type" => "text", "required" => true},
    {"name" => "kind", "label" => "Kind", "type" => "select", "options" => %w[news guide]},
    {"name" => "author", "label" => "Author", "type" => "group", "of" => [
      {"name" => "name", "label" => "Name", "type" => "string"},
      {"name" => "bio", "label" => "Bio", "type" => "markdown"}
    ]},
    {"name" => "cover", "label" => "Cover", "type" => "asset"},
    {"name" => "cta", "label" => "Call to action", "type" => "link"},
    {"name" => "event_at", "label" => "Event at", "type" => "datetime"},
    {"name" => "faqs", "label" => "FAQs", "type" => "repeater", "of" => [
      {"name" => "question", "label" => "Question", "type" => "string", "required" => true},
      {"name" => "answer", "label" => "Answer", "type" => "text"}
    ]},
    {"name" => "featured", "label" => "Featured", "type" => "boolean"},
    {"name" => "keywords", "label" => "Keywords", "type" => "string_list"},
    {"name" => "rating", "label" => "Rating", "type" => "integer"},
    {"name" => "source", "label" => "Source", "type" => "url"}
  ].freeze

  def seed_go_contract_site
    serve_over_api
    Setting.set("general", {"title" => "Acme", "email" => "hello@acme.example", "phone" => "+1 555 0100",
      "city" => "Springfield", "site_base_url" => "https://acme.example", "default_locale" => "en"})
    BlockType::Defaults.install!

    image = Asset.create!(folder: "/", name: "hero", alt: "A blue line",
      file: {io: File.open(Rails.root.join("public/icon.png")), filename: "hero.png", content_type: "image/png"})
    Branding.save(logo_id: image.id.to_s, favicon_id: image.id.to_s, primary_color: "#b45309", secondary_color: "#1c1917",
      font: "Playfair Display", border_radius: "medium", box_shadow: "small")

    posts = Collection.create!(slug: "posts", name: "Posts", api_enabled: true, schema: {"fields" => POSTS_FIELDS})
    posts.entries.create!(slug: "first-post", title: "First post", status: "published", published_at: 2.days.ago, locale: "en",
      body_markdown: "# First post\n\nWords.", seo: {"meta_description" => "First post, in brief.", "twitter_title" => "an old key"},
      frontmatter: {"summary" => "The first one.", "kind" => "news", "author" => {"name" => "Ada", "bio" => "Writes *things*.", "age" => 36},
        "cover" => image.id.to_s, "cta" => {"kind" => "url", "value" => "https://acme.example/signup"}, "event_at" => "2026-03-04T05:06:07Z",
        "faqs" => [{"question" => "Why?", "answer" => "Because.", "votes" => 3}], "featured" => true, "keywords" => %w[launch news],
        "rating" => 5, "source" => "https://source.example/a", "retired_field" => "left over"})
    @second_post = posts.entries.create!(slug: "second-post", title: "Second post", status: "published", published_at: 1.day.ago, locale: "en",
      body_markdown: "# Second post\n\nWords.", seo: {"meta_description" => "Second post, in brief."},
      frontmatter: {"summary" => "The second one.", "kind" => "guide", "author" => {}})
    posts.entries.create!(slug: "draft-post", title: "Draft post", status: "draft", locale: "en", frontmatter: {"summary" => "Not yet."})

    BlockPattern.create!(slug: "signoff", name: "Sign-off", synced: true,
      blocks: [{"id" => "p1", "type" => "quote", "data" => {"text" => "Built with care.", "attribution" => "Acme"}}])

    projects = Collection.create!(slug: "projects", name: "Projects", api_enabled: true, enable_blocks: true,
      schema: {"fields" => [{"name" => "client", "label" => "Client", "type" => "string", "required" => true},
        {"name" => "year", "label" => "Year", "type" => "integer"}]})
    projects.entries.create!(slug: "alpha", title: "Alpha", status: "published", published_at: 1.day.ago, locale: "en", body_markdown: "",
      frontmatter: {"client" => "Initech", "year" => 2025},
      blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "The *brief*.", "stale" => "x"}},
        {"id" => "b2", "type" => "pattern", "data" => {"pattern" => "signoff"}}])

    Page.create!(slug: "home", title: "Home", status: "published", published_at: 1.day.ago, locale: "en",
      seo: {"meta_title" => "Acme", "meta_description" => "What Acme does."},
      blocks: [
        {"id" => "b1", "type" => "hero", "data" => {"heading" => "Hello", "subheading" => "From Acme.", "image_id" => image.id.to_s,
          "ctas" => [{"label" => "Read the blog", "url" => {"kind" => "url", "value" => "/posts"}, "style" => "primary"}]}},
        {"id" => "b2", "type" => "collection_list", "data" => {"collection_slug" => "posts", "heading" => "Latest", "filter_status" => "published",
          "sort_by" => "title", "sort_dir" => "asc", "layout" => "list"}},
        {"id" => "b3", "type" => "contact_info", "data" => {"heading" => "Find us"}},
        {"id" => "b4", "type" => "pattern", "data" => {"pattern" => "signoff"}}
      ])
    @about = Page.create!(slug: "about", title: "About", status: "published", published_at: 1.day.ago, locale: "en",
      schema: {"fields" => [{"name" => "founded", "label" => "Founded", "type" => "datetime"},
        {"name" => "team_size", "label" => "Team size", "type" => "integer"}]},
      frontmatter: {"founded" => "2020-01-01T00:00:00Z", "team_size" => 12, "old_field" => "left over"},
      seo: {"meta_description" => "Who we are.", "canonical" => "https://acme.example/about-us",
        "json_ld" => {"@type" => "Organization", "name" => "Acme"}},
      blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "We make **things**."}}])
    Page.create!(slug: "draft", title: "Draft", status: "draft", locale: "en")

    Global.create!(slug: "nav", name: "Navigation", schema: {"fields" => [
      {"name" => "tagline", "label" => "Tagline", "type" => "string", "required" => true},
      {"name" => "links", "label" => "Links", "type" => "repeater", "of" => [
        {"name" => "label", "label" => "Label", "type" => "string"}, {"name" => "url", "label" => "Link", "type" => "link"}
      ]}
    ]}, data: {"tagline" => "Made by Acme.", "links" => [{"label" => "About", "url" => {"kind" => "page", "value" => "about"}}], "legacy" => true})

    Redirect.create!(source_path: "/old", destination_url: "/about", status_code: 301)
    Redirect.create!(source_path: "/blog/*", destination_url: "/posts/*", status_code: 302, wildcard: true)
  end
end

RSpec.configure { |config| config.include GoContractSite, type: :request }
