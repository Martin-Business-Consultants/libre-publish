# frozen_string_literal: true

require "rails_helper"

# The delivery API's contract, as the Go core records it and
# @librepublish/astro holds every site to (spec/fixtures/contracts/go, copied
# from librepublishgo's contracts/ by bin/contracts-sync and pinned in
# go.sha256). This CMS answers the same requests, from a site seeded the same
# way (GoContractSite), and has to give everything the Go core gives: every
# key, at the same place, of the same type; the same headers; the same
# webhook envelope and signatures; and a schema digest made byte for byte the
# same way. A key this CMS has and the Go core doesn't is a failure too,
# unless it's listed below (RAILS_ONLY), because the integration's records are
# strict: a key it doesn't know fails a site's build.
#
# What changes on purpose changes here: bin/contracts-sync after the Go
# core's contract moves, then make this pass, then docs/delivery-api.md.
RSpec.describe "Delivery contract (the Go core's, for @librepublish/astro)", type: :request do
  GO = Rails.root.join("spec/fixtures/contracts/go")
  INDEX = JSON.parse(GO.join("index.json").read).freeze

  # Keys this CMS sends that the Go core doesn't: kept for 1.x clients
  # (docs/compatibility.md), each where a strict reader doesn't look, but
  # one (marked) the integration has to accept.
  RAILS_ONLY = {
    "delivery/site.json" => ["data.description", "meta.api_version"],
    "delivery/sitemap.json" => ["data[].url", "data[].changefreq", "data[].priority", "meta.site_url"],
    "delivery/site-health.json" => ["data[].group", "data[].title", "data[].detail", "data[].ok", "data[].for_site", "meta.*"],
    "delivery/globals.json" => ["meta.total"],
    "delivery/redirects.json" => ["meta.total"],
    # A collection_list's entries carry their body: a key strict
    # @librepublish/astro 0.8.2 refuses (it takes it from rails-core on).
    "delivery/page-home.json" => ["data.blocks[].resolved.entries[].body_markdown"],
    "delivery/pages.json" => ["data[].blocks[].resolved.entries[].body_markdown"],
    # A full read says nothing was removed rather than leaving `removed` out.
    "delivery/content-full.json" => ["data.pages[].blocks[].resolved.entries[].body_markdown", "data.removed*"],
    "delivery/content-delta.json" => []
  }.freeze

  # Answered in full, compared by its own example below: its parts are the
  # site's block types, collections and globals.
  SHAPED_APART = ["delivery/schema.json"].freeze

  # Where this CMS's value may be null where the Go core's isn't: meta.since
  # on a full read (the Go core's is "").
  NULLABLE = ["meta.since"].freeze

  let(:token) { {"Authorization" => "Bearer #{create(:user).api_token.token}"} }

  def json = JSON.parse(response.body)

  def go(file) = JSON.parse(GO.join(file).read)

  # What a JSON value is made of: {"data.blocks[].type" => "string", …}.
  # Arrays merge their items' shapes ("[]"); records' own data (frontmatter,
  # block and global data, contact details, renditions…) is only its type,
  # since it's the site's, not the API's; `included`'s maps are keyed by "*".
  def shape(value, path = "", out = {})
    out[path] = (out[path].nil? || out[path] == "null") ? type_of(value) : out[path] if path != ""
    case value
    when Hash
      return out if opaque?(path)

      value.each { |key, item| shape(item, [path, keyed?(path) ? "*" : key].compact_blank.join("."), out) }
    when Array
      value.each { |item| shape(item, "#{path}[]", out) }
    end
    out
  end

  def opaque?(path)
    key = path.split(".").last.to_s
    %w[frontmatter seo plugin_config json_ld contact variants].include?(key) || (key == "data" && path != "data")
  end

  def keyed?(path) = path.match?(/\Aincluded\.(assets|entries|pages)\z/)

  def type_of(value)
    case value
    when Hash then "object"
    when Array then "array"
    when String then "string"
    when Integer then "integer"
    when Float then "number"
    when true, false then "boolean"
    else "null"
    end
  end

  def compatible?(path, ours, theirs)
    ours == theirs || theirs == "null" || (ours == "null" && NULLABLE.include?(path)) ||
      ([ours, theirs] - %w[integer number]).empty?
  end

  def differences(file, ours, theirs)
    missing = theirs.keys.reject { ours.key?(it) }
    mismatched = theirs.keys.select { ours.key?(it) && !compatible?(it, ours[it], theirs[it]) }.map { "#{it}: #{ours[it]}, not #{theirs[it]}" }
    allowed = RAILS_ONLY.fetch(file, [])
    extra = ours.keys.reject { |path| theirs.key?(path) || allowed.any? { path == it || path.start_with?(it.delete_suffix("*")) && it.end_with?("*") } }
    {missing:, mismatched:, extra:}.compact_blank
  end

  describe "the copy of the Go core's contract" do
    it "is the one go.sha256 pins (bin/contracts-sync rewrites both)" do
      pinned = Rails.root.join("spec/fixtures/contracts/go.sha256").read.lines.to_h { it.split("  ").map(&:strip).reverse }
      files = Dir.glob("**/*", base: GO.to_s).select { GO.join(it).file? } - %w[README.md COMMIT]

      expect(files.sort).to eq(pinned.keys.sort)
      files.each { expect(Digest::SHA256.file(GO.join(it)).hexdigest).to eq(pinned[it]), "#{it} differs from its pin" }
    end
  end

  describe "the schema digest" do
    it "is made byte for byte as the Go core makes it: canonical JSON of /api/v1/schema's data" do
      schema = go("delivery/schema.json")

      expect(CanonicalJson.digest(schema["data"])).to eq(schema["meta"]["schema_digest"])
      expect(INDEX.select { it.start_with?("delivery/") }.values.map { it.dig("headers", "X-CMS-Schema-Digest") }.uniq).to eq([schema["meta"]["schema_digest"]])
    end

    it "escapes and orders as Go's encoding/json does" do
      expect(CanonicalJson.generate({"b" => [1, 2.5, 3.0, nil, true], "a" => "<a href=\"x\">& \n\t\u0001é/</a>"}))
        .to eq(%({"a":"\\u003ca href=\\"x\\"\\u003e\\u0026\\u2028\\n\\t\\u0001é/\\u003c/a\\u003e","b":[1,2.5,3,null,true]}))
    end
  end

  describe "answers" do
    before { seed_go_contract_site }

    INDEX.select { |file, _| file.start_with?("delivery/") }.each do |file, entry|
      path = entry.dig("request", "path")

      it "#{path} answers as #{file} does" do
        if path.include?("<cursor>")
          get "/api/v1/content", headers: token
          cursor = json.dig("meta", "cursor")
          travel 1.minute
          @about.update!(title: "About Acme")
          @second_post.update!(status: "draft")
          path = path.sub("<cursor>", CGI.escape(cursor))
        end

        get path, headers: token

        expect(response.status).to eq(entry["status"])
        expect(response.headers["Content-Type"]).to eq(entry.dig("headers", "Content-Type"))
        expect(response.headers["Cache-Tag"].to_s.split(",")).to include(*entry.dig("headers", "Cache-Tag").split(","))
        expect(response.headers["X-CMS-Schema-Digest"]).to eq(DeliverySchema.digest).and(start_with("sha256:"))
        expect(differences(file, shape(json), shape(go(file)))).to eq({}) unless SHAPED_APART.include?(file)
      end
    end

    it "gives /api/v1/schema in the Go core's shape: closed JSON Schemas, patterns expanded, its digest in meta and the header" do
      get "/api/v1/schema", headers: token
      data = json["data"]
      theirs = go("delivery/schema.json")["data"]

      expect(json.dig("meta", "schema_digest")).to eq(CanonicalJson.digest(data)).and(eq(response.headers["X-CMS-Schema-Digest"]))
      expect(data.keys).to include(*theirs.keys)
      expect(data.keys - theirs.keys).to eq(["block_types"]) # deprecated: the shape before 1.34
      expect(data["blocks"].keys).to match_array(theirs["blocks"].keys)
      expect(data["collections"].keys).to match_array(theirs["collections"].keys)
      expect(data["globals"].keys).to match_array(theirs["globals"].keys)
      expect(data["pages"].keys).to match_array(theirs["pages"].keys)
      expect(data["seo"]["properties"].keys).to include(*theirs["seo"]["properties"].keys)

      %w[blocks collections globals pages].each do |part|
        data[part].each do |key, schema|
          expect(closed_everywhere(schema)).to eq([]), "#{part}/#{key} isn't closed at #{closed_everywhere(schema).join(", ")}"
          # The keys of the shape before 1.34, which JSON Schema reads as annotations.
          expect(schema.keys - %w[$schema type title properties required additionalProperties]).to all(be_in(%w[enable_blocks frontmatter data]))
        end
      end
      expect(closed_everywhere(data["seo"])).to eq([])
      # Field by field, as the Go core writes them.
      expect(data.dig("collections", "posts", "properties")).to eq(theirs.dig("collections", "posts", "properties"))
      expect(data.dig("globals", "nav").except("data")).to eq(theirs.dig("globals", "nav"))
      expect(data.dig("pages", "about").except("title", "frontmatter")).to eq(theirs.dig("pages", "about"))
    end

    it "delivers only what the schema declares: left-over keys stay in the record, not in what a site reads" do
      get "/api/v1/content", headers: token
      content = json["data"]
      first = content["entries"].find { it["slug"] == "first-post" }
      about = content["pages"].find { it["path"] == "about" }

      expect(first["frontmatter"].keys).not_to include("retired_field")
      expect(first.dig("frontmatter", "author")).to eq("name" => "Ada", "bio" => "Writes *things*.")
      expect(first.dig("frontmatter", "faqs")).to eq([{"question" => "Why?", "answer" => "Because."}])
      expect(first["seo"]).to eq("meta_description" => "First post, in brief.")
      expect(about["frontmatter"]).to eq("founded" => "2020-01-01T00:00:00Z", "team_size" => 12)
      expect(about["seo"]).to include("canonical_url" => "https://acme.example/about-us", "json_ld" => {"@type" => "Organization", "name" => "Acme"})
      expect(content["pages"].find { it["path"] == "home" }["frontmatter"]).to eq({})
      expect(content["globals"].first["data"].keys).to match_array(%w[tagline links])
      alpha = content["entries"].find { it["slug"] == "alpha" }
      expect(alpha["blocks"].map { [it["type"], it["data"]] }).to eq([["text", {"body" => "The *brief*."}], ["quote", {"text" => "Built with care.", "attribution" => "Acme"}]])
      expect(CollectionEntry.find_by!(slug: "first-post").frontmatter).to include("retired_field" => "left over")
    end

    it "answers OPTIONS on a resource with its JSON Schema" do
      process :options, "/api/v1/collections/posts/entries", headers: token

      expect(response).to have_http_status(:ok)
      expect(response.headers["Allow"]).to eq("GET, OPTIONS")
      expect(json).to include("resource" => "collections/posts/entries", "methods" => ["GET"])
      expect(json.dig("schema", "properties", "data", "items", "properties", "frontmatter", "properties").keys).to match_array(GoContractSite::POSTS_FIELDS.map { it["name"] })
    end

    it "pages a list in headers too, and gives what's asked for: ?fields=, ?include=" do
      get "/api/v1/collections/posts/entries", headers: token, params: {per: 1, fields: "title,seo.meta_description", include: "none"}

      expect([response.headers["X-Total-Count"], response.headers["X-Total-Pages"]]).to eq(%w[2 2])
      expect(response.headers["Link"]).to include('rel="first"', 'rel="next"', 'rel="last"').and(include("page=2"))
      expect(json["data"]).to eq([{"id" => json["data"][0]["id"], "title" => "First post", "seo" => {"meta_description" => "First post, in brief."}}])
      expect(json).not_to have_key("included")

      get "/api/v1/globals/nav", headers: token, params: {include: "pages"}
      expect(json.dig("included", "pages").keys).to eq(["about"])
    end

    it "answers 304 to a read that has what it would get" do
      get "/api/v1/pages/about", headers: token
      get "/api/v1/pages/about", headers: token.merge("If-None-Match" => response.headers["ETag"])

      expect(response).to have_http_status(:not_modified)
    end
  end

  describe "webhooks and purges" do
    let(:contract) { go("webhook_contract.json")["webhook"] }

    def capture
      sent = []
      allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, request|
        sent << request
        Net::HTTPOK.new("1.1", "200", "OK").tap { it.instance_variable_set(:@read, true) }
      end
      yield
      sent
    end

    def signed_as_the_go_core_signs?(request, secret)
      timestamp = request["X-CMS-Timestamp"]
      request["X-CMS-Signature"] == "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, request.body)}" &&
        request["X-CMS-Signature-V2"] == "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{request.body}")}" &&
        (Time.current.to_i - timestamp.to_i).abs < 5
    end

    INDEX.select { |file, _| file.start_with?("webhooks/") }.each do |file, entry|
      event = File.basename(file, ".json")
      next if event == "submission.created" # the Forms plugin's, from its own repository

      it "sends #{event} as #{file} is sent: the envelope, its data's keys, and the headers" do
        seed_go_contract_site
        webhook = Webhook.create!(name: "site", url: "https://hooks.acme.test/in", events: [event])
        payload = case event
        when /\Apage\./ then Page.find_by!(path: "home").webhook_payload
        when /\Aentry\./ then CollectionEntry.find_by!(slug: "first-post").webhook_payload
        when "global.updated" then Global.find_by!(slug: "nav").then { {id: it.id, slug: it.slug, name: it.name, updated_at: it.updated_at.iso8601} }
        when "schema.changed" then {schema_digest: DeliverySchema.digest}
        end

        sent = capture { webhook.deliver_now(event, payload.as_json) }
        theirs = go(file)
        body = JSON.parse(sent.first.body)

        expect(body.keys).to match_array(theirs.keys)
        expect(body["data"].keys).to include(*theirs["data"].keys)
        expect(entry["headers"].keys.map { sent.first[it].presence && it }).to eq(entry["headers"].keys)
        expect(sent.first["X-CMS-Event"]).to eq(event)
        expect(signed_as_the_go_core_signs?(sent.first, webhook.secret)).to be(true)
      end
    end

    it "gives a global's id in global.updated, as the Go core does" do
      seed_go_contract_site
      nav = Global.find_by!(slug: "nav")
      Webhook.create!(name: "site", url: "https://hooks.acme.test/in", events: ["global.updated"])

      expect { nav.update!(name: "Navigation") }.to have_enqueued_job(Webhook::DeliveryJob).with(anything, "global.updated", hash_including(id: nav.id))
    end

    it "announces schema.changed once the digest moves, and not before" do
      seed_go_contract_site
      DeliverySchema.announce_now # the first reading is only noted
      Webhook.create!(name: "site", url: "https://hooks.acme.test/in", events: ["schema.changed"])

      expect { DeliverySchema.announce_now }.not_to have_enqueued_job(Webhook::DeliveryJob)
      expect { BlockType.find_by!(slug: "quote").update!(label: "Pull quote") }.to have_enqueued_job(DeliverySchema::AnnounceJob)
      expect { DeliverySchema.announce_now }.to have_enqueued_job(Webhook::DeliveryJob).with(anything, "schema.changed", {schema_digest: DeliverySchema.digest})
    end

    it "announces schema.changed against the schema the site's last build was checked against, before any announcement" do
      seed_go_contract_site
      Frontend.record_build("render" => "static", "schema_digest" => DeliverySchema.digest)
      Webhook.create!(name: "site", url: "https://hooks.acme.test/in", events: ["schema.changed"])
      Collection.find_by!(slug: "posts").update!(name: "Articles")

      expect { DeliverySchema.announce_now }.to have_enqueued_job(Webhook::DeliveryJob).with(anything, "schema.changed", {schema_digest: DeliverySchema.digest})
    end

    it "signs an on-demand site's purge as webhooks are signed" do
      sent = capture { Deploys::Purge.fire(reason: "page.published", changes: [], url: "https://acme.test/_cms/webhook", secret: "purge-secret") }

      expect(signed_as_the_go_core_signs?(sent.first, "purge-secret")).to be(true)
      expect(sent.first["X-CMS-Delivery"]).to be_present
    end

    it "keeps the webhook contract the Go core publishes" do
      expect(JSON.parse(Rails.root.join("spec/fixtures/contracts/webhook_contract.json").read)["webhook"]).to eq(contract)
      expect(contract["events"]).to include(*Webhook::EVENTS)
    end
  end

  # Every object schema with properties, closed; [] when all are. Paths of
  # the open ones otherwise. A link's {kind, value, collection} stays open,
  # as the Go core has it, and a blocks field's items are each block's.
  def closed_everywhere(schema, path = "")
    return [] unless schema.is_a?(Hash)

    return [] if schema["x-cms-type"].in?(%w[link blocks])

    own = schema["type"] == "object" && schema["properties"] && schema["additionalProperties"] != false ? [path] : []
    nested = (schema["properties"] || {}).flat_map { |key, child| closed_everywhere(child, "#{path}.#{key}") }
    own + nested + closed_everywhere(schema["items"], "#{path}.items")
  end
end
