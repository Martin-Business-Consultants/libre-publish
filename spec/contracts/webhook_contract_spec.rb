# frozen_string_literal: true

require "rails_helper"
require "openssl"

# What a webhook receiver can rely on (spec/fixtures/contracts/
# webhook_contract.json, docs/webhooks.md): the envelope, its signature, the
# events, and the keys of a page's or entry's payload. A receiver matches a
# payload to a record by its URL, so that has to be the address the site
# publishes.
#
# If you change a payload shape here, the fixture changes with it, and so
# does what every receiver sees — that is the point, not an inconvenience.
RSpec.describe "Webhook contract", type: :request do
  CONTRACT = JSON.parse(
    File.read(Rails.root.join("spec/fixtures/contracts/webhook_contract.json"))
  ).freeze

  def json = JSON.parse(response.body)

  def auth_headers(capabilities)
    actor = create(:user, admin: false, role: create(:role, permissions: capabilities))
    {"Authorization" => "Bearer #{actor.api_token.token}"}
  end

  # --- What the CMS sends ---------------------------------------------------

  describe "content webhook payloads" do
    let(:page) {
      Page.create!(title: "About us", slug: "about", status: "published", locale: "en",
        blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {})
    }

    before { Setting.set("general", {"site_base_url" => "https://acme.test"}) }

    it "publishes exactly the documented keys for a page" do
      expect(page.webhook_payload.keys.map(&:to_s).sort)
        .to eq(CONTRACT.dig("webhook", "page_data_keys").sort)
    end

    it "publishes exactly the documented keys for an entry" do
      collection = Collection.create!(name: "Posts", slug: "posts", schema: {"fields" => []})
      entry = collection.entries.create!(title: "Hello", slug: "hello", status: "published",
        locale: "en", blocks: [], frontmatter: {}, seo: {})

      expect(entry.webhook_payload.keys.map(&:to_s).sort)
        .to eq(CONTRACT.dig("webhook", "entry_data_keys").sort)
    end

    # A receiver matches a payload to the page it describes by URL (rows from
    # search or analytics come keyed by address), so every payload carries one.
    it "carries an absolute url" do
      expect(page.webhook_payload[:url]).to eq("https://acme.test/about")
    end

    it "publishes the same address the sitemap does" do
      page_id = page.id # force it into existence before the sitemap is built
      sitemap_entry = Sitemap.new.entries.find { |e| e.id == page_id && e.source == "page" }

      expect(sitemap_entry).to be_present
      expect(page.public_path).to eq(sitemap_entry.loc)
    end

    it "honours an SEO canonical, as the sitemap does" do
      page.update!(seo: {"canonical" => "/about-us"})

      expect(page.webhook_payload[:url]).to eq("https://acme.test/about-us")
    end

    it "honours the canonical_url key the admin SEO panel saves" do
      page.update!(seo: {"canonical_url" => "/about-us"})

      expect(page.public_url).to eq("https://acme.test/about-us")
      expect(page.webhook_payload[:url]).to eq("https://acme.test/about-us")
    end

    it "falls back to a relative url rather than inventing an origin" do
      Setting.set("general", {"site_base_url" => ""})

      expect(page.webhook_payload[:url]).to eq("/about")
    end

    # The contract also lists the Forms and Commerce plugins' events, which
    # the core emits only while they're installed.
    it "emits only documented events" do
      expect(Webhook.events - CONTRACT.dig("webhook", "events")).to be_empty
    end
  end

  describe "the delivery envelope" do
    let(:webhook) {
      Webhook.create!(name: "receiver", url: "https://hooks.acme.test/content",
        events: ["page.published"], secret: "site-webhook-secret")
    }

    it "wraps the payload in the documented envelope and signs the raw body" do
      captured = nil
      allow_any_instance_of(Net::HTTP).to receive(:request) do |_self, req|
        captured = req
        Class.new(Net::HTTPSuccess).new("1.1", "200", "OK").tap do |r|
          def r.body = "ok"
          def r.code = "200"
        end
      end

      DeliverWebhookJob.perform_now(webhook.id, "page.published", {slug: "about"})

      envelope = JSON.parse(captured.body)
      expect(envelope.keys.sort).to eq(CONTRACT.dig("webhook", "envelope_keys").sort)
      expect(envelope["tenant"]).to eq(Site.key)

      header = CONTRACT.dig("webhook", "signature_header")
      expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, captured.body)
      expect(captured[header]).to eq(expected)
    end
  end
end
