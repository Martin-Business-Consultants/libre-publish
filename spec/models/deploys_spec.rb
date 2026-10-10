# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deploys do
  def http_stub(response)
    http = instance_double(Net::HTTP, "use_ssl=": nil, "open_timeout=": nil, "read_timeout=": nil, "ipaddr=": nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) { |request| @request = request; response }
    http
  end

  describe ".current" do
    it "keeps an install with a build hook on the build hook" do
      Setting.set("deploy", {"url" => "https://hooks.example.com/x"})

      expect(described_class.current).to be_a(Deploys::BuildHook)
      expect(described_class.current.target).to eq("hooks.example.com")
    end

    it "defaults to GitHub otherwise" do
      expect(described_class.current).to be_a(Deploys::Github)
      expect(described_class.current).not_to be_configured
    end

    it "uses the provider Settings › Deploy chose" do
      Setting.set("deploy", {"url" => "https://hooks.example.com/x", "provider" => "github"})

      expect(described_class.current).to be_a(Deploys::Github)
    end
  end

  describe Deploys::Github do
    before { Setting.set("github", {"token" => "ghp_secret", "frontend_github_repo" => "acme/acme-site"}) }

    it "sends a repository_dispatch to the site's repo" do
      http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

      attempt = Deploys::Github.new.fire(reason: "page.published")

      expect(attempt.status).to eq("success")
      expect(attempt.http_status).to eq(204)
      expect(@request.path).to eq("/repos/acme/acme-site/dispatches")
      expect(@request["Authorization"]).to eq("Bearer ghp_secret")
      expect(JSON.parse(@request.body)).to include("event_type" => "cms-publish",
        "client_payload" => {"reason" => "page.published", "site" => Site.key, "changes" => []})
    end

    it "records a refused dispatch as a failure" do
      http_stub(Net::HTTPNotFound.new("1.1", "404", "Not Found"))

      expect(Deploys::Github.new.fire(reason: "manual").status).to eq("failure")
    end

    it "runs through Deploys::TriggerJob and its log" do
      Setting.set("deploy", {"provider" => "github", "scheduled_at" => "t"})
      http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

      Deploys::TriggerJob.perform_now("t", "manual")

      expect(Setting.get("deploy")["log"].first).to include("status" => "success", "http_status" => 204, "reason" => "manual")
    end
  end

  # The job and the stamp it checks share one timestamp. Two Time.current
  # calls a few microseconds apart made every manual deploy skip itself.
  it "fires a manual deploy in real time rather than skipping it as superseded" do
    Setting.set(Deploys::SETTING_KEY, "url" => "https://build.example/hook", "provider" => "build_hook")
    allow_any_instance_of(Deploys::BuildHook).to receive(:fire).and_return(Deploys::Attempt.new(status: "success", http_status: 200))

    job = Deploys.trigger_later
    scheduled_at = job.arguments.first
    expect(Setting.get(Deploys::SETTING_KEY)["scheduled_at"]).to eq(scheduled_at)

    Deploys::TriggerJob.perform_now(*job.arguments)
    expect(Setting.get(Deploys::SETTING_KEY)["last_status"]).to eq("success")
  end

  describe "what changed" do
    include ActiveJob::TestHelper

    let(:page) { Page.create!(slug: "about", title: "About", status: "published", locale: "en") }

    it "describes a page, an entry and a global with the site's cache tags" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      entry = collection.entries.create!(slug: "hello", title: "Hello", status: "published", locale: "en")
      global = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})

      expect(Deploys::Change.from("page.published", page)).to eq("event" => "page.published", "kind" => "page", "id" => page.id,
        "path" => "/about", "locale" => "en", "tags" => %w[page:about pages sitemap])
      expect(Deploys::Change.from("entry.updated", entry)["tags"]).to eq(%w[entry:posts/hello collection:posts sitemap])
      expect(Deploys::Change.from("global.updated", global)).to include("kind" => "global", "tags" => %w[global:footer])
    end

    it "keeps one change per record in a window, with its latest event" do
      first = Deploys::Change.from("page.updated", page)
      other = Deploys::Change.from("page.published", Page.create!(slug: "team", title: "Team", status: "published", locale: "en"))

      merged = Deploys::Change.merge([first, other, first.merge("event" => "page.unpublished")])

      expect(merged.map { it["event"] }).to eq(%w[page.published page.unpublished])
    end

    it "sends a static site's build the window's changes" do
      Setting.set("github", {"token" => "ghp_secret", "frontend_github_repo" => "acme/acme-site"})
      Setting.set("deploy", {"provider" => "github"})
      Frontend.record_build("render" => "static")
      http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

      described_class.schedule_later(reason: "page.published", subject: page)
      described_class.schedule_later(reason: "page.updated", subject: page)
      perform_enqueued_jobs(only: Deploys::TriggerJob) { described_class.trigger_now(Setting.get("deploy")["scheduled_at"], "page.updated") }

      payload = JSON.parse(@request.body)["client_payload"]
      expect(payload["changes"]).to eq([Deploys::Change.from("page.updated", page)])
      expect(Setting.get("deploy")["pending_changes"]).to eq([])
      expect(Setting.get("deploy")["log"].first).to include("via" => "github", "changes" => 1)
    end

    describe "when it fires" do
      before do
        Setting.set("github", {"token" => "ghp_secret", "frontend_github_repo" => "acme/acme-site"})
        Setting.set("deploy", {"provider" => "github"})
        Frontend.record_build("render" => "static")
      end

      it "keeps the changes for the next deploy when the build fails" do
        http_stub(Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error"))

        described_class.schedule_later(reason: "page.updated", subject: page)
        described_class.trigger_now(Setting.get("deploy")["scheduled_at"], "page.updated")

        expect(Setting.get("deploy")["last_status"]).to eq("failure")
        expect(Setting.get("deploy")["pending_changes"]).to include(Deploys::Change.from("page.updated", page))
      end

      it "fires once when its job runs twice" do
        http = http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))

        described_class.schedule_later(reason: "page.updated", subject: page)
        scheduled_at = Setting.get("deploy")["scheduled_at"]
        2.times { described_class.trigger_now(scheduled_at, "page.updated") }

        expect(http).to have_received(:request).once
      end

      it "leaves what changed while it fired, and the schedule that brought it, for the next deploy" do
        team = Page.create!(slug: "team", title: "Team", status: "draft", locale: "en")
        http = http_stub(Net::HTTPNoContent.new("1.1", "204", "No Content"))
        allow(http).to receive(:request) do
          described_class.schedule_later(reason: "page.published", subject: team)
          Net::HTTPNoContent.new("1.1", "204", "No Content")
        end

        described_class.schedule_later(reason: "page.updated", subject: page)
        described_class.trigger_now(Setting.get("deploy")["scheduled_at"], "page.updated")

        deploy = Setting.get("deploy")
        expect(deploy["pending_changes"]).to eq([Deploys::Change.from("page.published", team)])
        expect(deploy["scheduled_at"]).to be_present
        expect(deploy["last_status"]).to eq("success")
      end
    end

    it "purges a site rendered on demand instead of rebuilding it, signed with its secret" do
      Setting.set("deploy", {"provider" => "build_hook", "url" => "https://build.example/hook"})
      Frontend.record_build("render" => "server", "webhook_url" => "https://acme.test/_cms/webhook")
      Frontend.approve_delivery!
      http_stub(Net::HTTPOK.new("1.1", "200", "OK"))

      described_class.schedule_later(reason: "page.published", subject: page)
      described_class.trigger_now(Setting.get("deploy")["scheduled_at"], "page.published")

      expect(@request.path).to eq("/_cms/webhook")
      expect(@request["X-CMS-Event"]).to eq("cms.purge")
      expect(@request["X-CMS-Signature"]).to eq("sha256=#{OpenSSL::HMAC.hexdigest("SHA256", Frontend.purge_secret, @request.body)}")
      body = JSON.parse(@request.body)
      expect(body).to include("event" => "cms.purge", "reason" => "page.published", "all" => false,
        "tags" => %w[page:about pages sitemap])
      expect(Setting.get("deploy")["log"].map { it["via"] }).to eq(["purge"])
    end

    it "rebuilds a hybrid site's prerendered pages and purges the rest" do
      Setting.set("deploy", {"provider" => "cloudflare", "url" => "https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/x"})
      Frontend.record_build("render" => "hybrid", "webhook_url" => "https://acme.test/_cms/webhook")
      Frontend.approve_delivery!
      paths = []
      http = http_stub(Net::HTTPOK.new("1.1", "200", "OK"))
      allow(http).to receive(:request) { |request| paths << request.path; Net::HTTPOK.new("1.1", "200", "OK") }

      described_class.schedule_later(reason: "page.published", subject: page)
      described_class.trigger_now(Setting.get("deploy")["scheduled_at"], "page.published")

      expect(paths).to eq(["/_cms/webhook", "/client/v4/pages/webhooks/deploy_hooks/x"])
      expect(Setting.get("deploy")["log"].map { it["via"] }).to eq(%w[cloudflare purge])
    end

    it "asks a server site to purge everything on Deploy now, and rebuilds it too" do
      Setting.set("deploy", {"provider" => "build_hook", "url" => "https://build.example/hook"})
      Frontend.record_build("render" => "server", "webhook_url" => "https://acme.test/_cms/webhook")
      Frontend.approve_delivery!
      bodies = []
      http = http_stub(Net::HTTPOK.new("1.1", "200", "OK"))
      allow(http).to receive(:request) { |request| bodies << request.body; Net::HTTPOK.new("1.1", "200", "OK") }

      job = described_class.trigger_later
      Deploys::TriggerJob.perform_now(*job.arguments)

      expect(JSON.parse(bodies.first)).to include("all" => true)
      expect(Setting.get("deploy")["log"].map { it["via"] }).to eq(%w[build_hook purge])
    end

    it "is ready with only a purge URL, and tells a plugin's provider only what it takes" do
      expect(described_class.ready?).to be(false)
      Frontend.record_build("render" => "server", "webhook_url" => "https://acme.test/_cms/webhook")
      Frontend.approve_delivery!
      expect(described_class.ready?).to be(true)

      legacy = Class.new(Deploys::Provider) do
        def configured? = true
        def fire(reason:) = Deploys::Attempt.new(status: "success", http_status: 200)
      end
      expect(described_class.fire(legacy.new, "manual", [{"event" => "x"}]).status).to eq("success")
    end
  end

  describe Deploys::Cloudflare do
    it "is offered beside the build hook and GitHub, and posts to its deploy hook" do
      expect(Deploys.providers.keys).to include("build_hook", "cloudflare", "github")
      Setting.set("deploy", {"provider" => "cloudflare", "url" => "https://api.cloudflare.com/client/v4/workers/builds/deploy_hooks/abc"})
      http_stub(Net::HTTPOK.new("1.1", "200", "OK"))

      expect(Deploys.current).to be_a(Deploys::Cloudflare)
      expect(Deploys.current.label).to eq("Cloudflare (Pages or Workers Builds deploy hook)")
      expect(Deploys.current.fire(reason: "manual").status).to eq("success")
      expect(@request.path).to eq("/client/v4/workers/builds/deploy_hooks/abc")
    end
  end

  describe "sending to the site's own URLs" do
    it "won't fire a build hook that points inside the network" do
      Setting.set("deploy", {"url" => "http://ci.internal.example.com/build"})
      OutboundUrl.resolver = ->(_host) { ["192.168.1.20"] }
      expect(Net::HTTP).not_to receive(:new)

      attempt = Deploys.current.fire(reason: "manual")

      expect(attempt.status).to eq("failure")
      expect(attempt.error).to match(/private or local/)
    end

    it "won't send a purge to a webhook URL that points inside the network" do
      OutboundUrl.resolver = ->(_host) { ["127.0.0.1"] }
      expect(Net::HTTP).not_to receive(:new)

      attempt = Deploys::Purge.fire(reason: "manual", changes: [], url: "http://site.example.com/_cms/webhook", secret: "s")

      expect(attempt.status).to eq("failure")
      expect(attempt.error).to match(/private or local/)
    end

    it "pins a build hook's request to the address it checked" do
      Setting.set("deploy", {"url" => "https://hooks.example.com/x"})
      http = http_stub(Net::HTTPOK.new("1.1", "200", "OK"))

      expect(Deploys.current.fire(reason: "manual").status).to eq("success")
      expect(http).to have_received(:ipaddr=).with("203.0.113.10")
    end
  end
end
