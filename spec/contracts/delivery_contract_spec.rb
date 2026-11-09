# frozen_string_literal: true

require "rails_helper"

# The delivery API's contract (contracts/, docs/delivery-api.md): the answers
# a site builds from, recorded from a seeded install. The Astro integration
# (integrations/astro) runs its tests on the same files — its loaders and
# schemas must take every recorded record, and its digest must reproduce the
# recorded X-CMS-Schema-Digest — so neither side can drift from the other
# without a test failing.
#
# A change that moves an answer fails here until the files are rewritten:
#
#   RECORD_CONTRACTS=1 bin/rspec spec/contracts/delivery_contract_spec.rb
#
# and rewritten files fail the integration's tests until it follows
# (integrations/astro/test/contracts.sha256 pins what it was last checked
# against). Review the diff of contracts/ like any other change to the API.
RSpec.describe "Delivery contract", type: :request do
  CONTRACTS = Rails.root.join("contracts")
  RECORDED_HEADERS = %w[Content-Type Cache-Tag X-CMS-Schema-Digest].freeze
  TIME_KEYS = %w[published_at updated_at created_at lastmod].freeze
  FIXED_TIME = "2026-01-01T00:00:00Z"

  # name → path. Each is requested in this order and written to
  # contracts/delivery/<name>.json.
  REQUESTS = {
    "site" => "/api/v1/site",
    "schema" => "/api/v1/schema",
    "content-full" => "/api/v1/content",
    "pages" => "/api/v1/pages",
    "page-home" => "/api/v1/pages/home",
    "page-about" => "/api/v1/pages/about",
    "page-nested" => "/api/v1/pages/company/team",
    "collections" => "/api/v1/collections",
    "collection-posts" => "/api/v1/collections/posts",
    "entries-posts" => "/api/v1/collections/posts/entries",
    "entry-post" => "/api/v1/collections/posts/entries/hello-world",
    "entries-projects" => "/api/v1/collections/projects/entries",
    "globals" => "/api/v1/globals",
    "global-footer" => "/api/v1/globals/footer",
    "sitemap" => "/api/v1/sitemap",
    "robots" => "/api/v1/robots",
    "redirects" => "/api/v1/redirects",
    "page-missing" => "/api/v1/pages/nowhere",
    "page-draft" => "/api/v1/pages/unfinished"
  }.freeze

  let(:token) { {"Authorization" => "Bearer #{create(:user).api_token.token}"} }

  def upload(path, type) = Asset.upload!(Rack::Test::UploadedFile.new(Rails.root.join(path), type), folder: "/images", alt: "The logo")

  # A small site with every field type, live and draft records, a collection
  # with blocks, a collection list, nested pages, a global, an asset and a
  # redirect -- and keys left over from older data at every depth (`stale`),
  # plus blocks whose type is gone, none of which may be delivered.
  def seed!
    # Record ids appear in the answers. SQLite's autoincrement counters
    # outlive a rolled-back example, so start them over: the same ids
    # whatever ran before.
    ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence")
    serve_over_api
    Setting.set("general", Setting.get("general").merge(
      "title" => "Acme", "site_base_url" => "https://acme.example", "serving" => "api_only", "api_pages" => true
    ))

    png = upload("public/icon.png", "image/png")
    svg = upload("public/icon.svg", "image/svg+xml")

    every_field = [
      {"name" => "title", "label" => "Title", "type" => "string", "required" => true},
      {"name" => "summary", "label" => "Summary", "type" => "text"},
      {"name" => "body", "label" => "Body", "type" => "markdown"},
      {"name" => "embed", "label" => "Embed", "type" => "code"},
      {"name" => "count", "label" => "Count", "type" => "integer"},
      {"name" => "featured", "label" => "Featured", "type" => "boolean"},
      {"name" => "tone", "label" => "Tone", "type" => "select", "options" => %w[light dark]},
      {"name" => "website", "label" => "Website", "type" => "url"},
      {"name" => "starts_at", "label" => "Starts", "type" => "datetime"},
      {"name" => "cta", "label" => "Button", "type" => "link"},
      {"name" => "image", "label" => "Image", "type" => "asset"},
      {"name" => "post", "label" => "Post", "type" => "record_ref", "of_collection" => "posts"},
      {"name" => "posts", "label" => "Posts", "type" => "record_refs", "of_collection" => "posts"},
      {"name" => "tags", "label" => "Tags", "type" => "string_list"},
      {"name" => "items", "label" => "Items", "type" => "repeater", "of" => [
        {"name" => "label", "label" => "Label", "type" => "string", "required" => true},
        {"name" => "icon", "label" => "Icon", "type" => "asset"}
      ]},
      {"name" => "contact", "label" => "Contact", "type" => "group", "of" => [
        {"name" => "phone", "label" => "Phone", "type" => "string"},
        {"name" => "link", "label" => "Link", "type" => "link"}
      ]},
      {"name" => "inner", "label" => "Inner blocks", "type" => "blocks", "allowed_types" => %w[text]}
    ]
    BlockType.create!(slug: "text", label: "Text", fields: [{"name" => "body", "label" => "Body", "type" => "markdown"}])
    BlockType.create!(slug: "every_field", label: "Every field", fields: every_field)
    BlockType.create!(slug: "collection_list", label: "Collection list", fields: [
      {"name" => "collection_slug", "label" => "Collection", "type" => "string", "required" => true},
      {"name" => "heading", "label" => "Heading", "type" => "string"},
      {"name" => "filter_status", "label" => "Status", "type" => "select", "options" => %w[published any]},
      {"name" => "sort_by", "label" => "Sort by", "type" => "select", "options" => %w[published_at title]},
      {"name" => "sort_dir", "label" => "Direction", "type" => "select", "options" => %w[desc asc]},
      {"name" => "limit", "label" => "Limit", "type" => "integer"}
    ])
    BlockType.create!(slug: "contact_info", label: "Contact info", fields: [{"name" => "heading", "label" => "Heading", "type" => "string"}])
    BlockType.create!(slug: "retired", label: "Retired", deprecated: true, fields: [{"name" => "note", "label" => "Note", "type" => "string"}])

    posts = Collection.create!(slug: "posts", name: "Posts", routable: true, schema: {"fields" => [
      {"name" => "summary", "label" => "Summary", "type" => "text", "required" => true},
      {"name" => "cover", "label" => "Cover", "type" => "asset"},
      {"name" => "category", "label" => "Category", "type" => "select", "options" => %w[news guides]},
      {"name" => "date", "label" => "Date", "type" => "datetime"}
    ]})
    projects = Collection.create!(slug: "projects", name: "Projects", enable_blocks: true, schema: {"fields" => [
      {"name" => "client", "label" => "Client", "type" => "string"}
    ]})

    posts.entries.create!(slug: "hello-world", title: "Hello, world", status: "published", locale: "en",
      published_at: 2.days.ago, body_markdown: "# Hello\n\nThe <first> post & more.",
      frontmatter: {"summary" => "The first post.", "cover" => png.id.to_s, "category" => "news", "date" => "2026-01-01T09:00:00Z"},
      seo: {"meta_title" => "Hello", "meta_description" => "The first post.", "og_image_id" => png.id.to_s})
    posts.entries.create!(slug: "second", title: "Second", status: "published", locale: "en", published_at: 1.day.ago,
      frontmatter: {"summary" => "Another.", "stale" => "x"})
    posts.entries.create!(slug: "not-yet", title: "Not yet", status: "draft", locale: "en", frontmatter: {"summary" => "Draft."})
    projects.entries.create!(slug: "alpha", title: "Alpha", status: "published", locale: "en", published_at: 1.day.ago,
      frontmatter: {"client" => "Acme"},
      blocks: [{"id" => "p1", "type" => "text", "data" => {"body" => "A project."}}])

    Global.create!(slug: "footer", name: "Footer", schema: {"fields" => [
      {"name" => "copyright", "label" => "Copyright", "type" => "string"},
      {"name" => "logo", "label" => "Logo", "type" => "asset"},
      {"name" => "links", "label" => "Links", "type" => "repeater", "of" => [
        {"name" => "label", "label" => "Label", "type" => "string"},
        {"name" => "href", "label" => "Link", "type" => "link"}
      ]}
    ]}, data: {"copyright" => "© Acme", "logo" => svg.id.to_s, "stale" => "x",
               "links" => [{"label" => "About", "href" => {"kind" => "page", "value" => "about"}}]})

    Page.create!(slug: "home", title: "Home", status: "published", locale: "en", published_at: 3.days.ago,
      seo: {"meta_title" => "Acme", "meta_description" => "What Acme does.", "stale" => "x"},
      blocks: [
        {"id" => "b1", "type" => "every_field", "data" => {
          "title" => "Every field", "summary" => "Plain text\non two lines.", "body" => "**Bold** and a [link](/about).",
          "embed" => "<div class=\"x\">&nbsp;</div>", "count" => 3, "featured" => true, "tone" => "dark",
          "website" => "https://example.org", "starts_at" => "2026-01-01T09:00:00Z",
          "cta" => {"kind" => "entry", "value" => "hello-world", "collection" => "posts"},
          "image" => png.id.to_s, "post" => "hello-world", "posts" => %w[hello-world second], "tags" => %w[a b],
          "items" => [{"label" => "One", "icon" => svg.id.to_s, "stale" => true}, {"label" => "Two"}],
          "contact" => {"phone" => "555-0100", "stale" => "x", "link" => {"kind" => "url", "value" => "https://example.org/contact", "stale" => "x"}},
          "inner" => [{"type" => "text", "data" => {"body" => "Nested.", "stale" => 1}, "stale" => 1}],
          "stale" => "a field since removed"
        }},
        {"id" => "b2", "type" => "collection_list", "data" => {"collection_slug" => "posts", "heading" => "Latest",
                                                               "filter_status" => "published", "sort_by" => "published_at", "sort_dir" => "desc", "limit" => 10}},
        {"id" => "b3", "type" => "contact_info", "data" => {"heading" => "Find us"}}
      ])
    about = Page.create!(slug: "about", title: "About", status: "published", locale: "en", published_at: 3.days.ago,
      blocks: [{"id" => "a1", "type" => "text", "data" => {"body" => "About Acme."}}])
    company = Page.create!(slug: "company", title: "Company", status: "published", locale: "en", published_at: 3.days.ago)
    Page.create!(slug: "team", title: "Team", status: "published", locale: "en", parent: company, published_at: 3.days.ago,
      blocks: [{"id" => "t1", "type" => "text", "data" => {"body" => "The team."}}])
    Page.create!(slug: "unfinished", title: "Unfinished", status: "draft", locale: "en")
    about.touch

    Redirect.create!(source_path: "/old-about", destination_url: "/about", status_code: 301)

    # Blocks whose type has since been deleted, written straight to the
    # column as a deletion leaves them: there's no schema for them to be held to.
    home = Page.find_by!(slug: "home")
    blocks = home.blocks.deep_dup
    blocks.first["data"]["inner"] << {"type" => "gone", "data" => {"body" => "No type."}}
    blocks << {"id" => "b0", "type" => "gone", "data" => {"body" => "Its block type was deleted."}}
    home.update_columns(blocks: blocks)
  end

  # What changes from run to run, made stable: times, the content cursor,
  # Active Storage's signed blob ids and variation keys.
  def normalize(value, key = nil)
    case value
    when Hash then value.to_h { |k, v| [k, normalize(v, k)] }.sort.to_h
    when Array then value.map { normalize(it) }
    when String
      if TIME_KEYS.include?(key) && value.match?(/\A\d{4}-\d{2}-\d{2}/) then FIXED_TIME
      elsif key == "cursor" then "<cursor>"
      else
        value.gsub(%r{/rails/active_storage/(blobs|representations)/(redirect|proxy)/[^/]+/(?:[^/]+/)?}) { "/rails/active_storage/#{$1}/#{$2}/<blob>/" }
      end
    else value
    end
  end

  def recorded_headers
    RECORDED_HEADERS.filter_map { |h| [h, response.headers[h]] if response.headers[h] }.to_h
  end

  it "answers every request as recorded in contracts/" do
    travel_to(Time.utc(2026, 1, 1, 12)) { seed! }

    index = {}
    answers = {}
    REQUESTS.each do |name, path|
      get path, headers: token
      answers[name] = response.body.present? ? normalize(JSON.parse(response.body)) : nil
      index[name] = {"request" => {"method" => "GET", "path" => path}, "status" => response.status, "headers" => recorded_headers}
    end

    # The digest every answer carries is the schema's: CanonicalJson of /schema's data.
    expect(index.values.filter_map { it.dig("headers", "X-CMS-Schema-Digest") }.uniq)
      .to eq([CanonicalJson.digest(JSON.parse(response_for_schema(answers)))])
    expect(answers.dig("schema", "meta", "schema_digest")).to eq(index.dig("schema", "headers", "X-CMS-Schema-Digest"))

    # Nothing the schema doesn't declare is delivered, at any depth.
    leaks = answers.except("schema").select { |_, body| JSON.generate(body).match?(/stale|No type\.|Its block type was deleted/) }
    expect(leaks.keys).to be_empty, -> { "Undeclared keys delivered in: #{leaks.map { |name, body| "#{name}: #{JSON.generate(body).scan(/.{0,80}(?:stale|No type\.|block type was deleted).{0,40}/).first}" }.join("\n")}" }

    files = answers.to_h { |name, body| ["delivery/#{name}.json", body] }
    files["index.json"] = index

    if ENV["RECORD_CONTRACTS"].present?
      files.each do |file, body|
        CONTRACTS.join(file).dirname.mkpath
        CONTRACTS.join(file).write("#{JSON.pretty_generate(body)}\n")
      end
      stale = CONTRACTS.glob("delivery/*.json").map { it.relative_path_from(CONTRACTS).to_s } - files.keys
      stale.each { CONTRACTS.join(it).delete }
    else
      files.each do |file, body|
        path = CONTRACTS.join(file)
        expect(path).to exist, "contracts/#{file} is missing: RECORD_CONTRACTS=1 bin/rspec #{__FILE__}"
        expect(JSON.parse(path.read)).to eq(JSON.parse(JSON.generate(body))),
          "contracts/#{file} differs from the API's answer. If the change is meant, rewrite the files " \
          "(RECORD_CONTRACTS=1 bin/rspec #{__FILE__}) and update integrations/astro to follow."
      end
    end
  end

  def response_for_schema(answers) = JSON.generate(answers.dig("schema", "data"))
end
