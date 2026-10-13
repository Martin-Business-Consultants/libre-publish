# frozen_string_literal: true

require "rails_helper"

# Settings › Security policy: the website's Content-Security-Policy (off,
# report only, enforced), the services and sources it allows, strict inline
# scripts, the admin's extra sources, and what browsers report blocked.
RSpec.describe "Security policy", type: :request do
  let(:admin) { create(:user) }

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  before do
    BlockType::Defaults.install!
    Page.create!(slug: "home", title: "Home", status: "published", locale: "en")
    SiteSetup.new(name: "Acme", owner_email: "owner@example.com").call if Global.find_by(slug: "scripts").nil?
    Global.find_by!(slug: "scripts").update!(data: {"items" => [{"name" => "GA4",
      "head" => %(<script async src="https://www.googletagmanager.com/gtag/js?id=G-1"></script><script>gtag("config","G-1")</script>),
      "body" => %(<script src="https://widget.chat.example/w.js"></script>)}]})
  end

  it "sends none on the website until it's turned on, then report only or enforced, with what's allowed" do
    get "/"
    expect(response.headers["Content-Security-Policy"]).to be_nil
    expect(response.headers["Content-Security-Policy-Report-Only"]).to be_nil

    SecurityPolicy.update(mode: "report", presets: %w[google_analytics], sources: {"script-src" => "https://widget.chat.example"})
    get "/"
    header = response.headers["Content-Security-Policy-Report-Only"]
    expect(header).to include("default-src 'self'", "script-src 'self' 'unsafe-inline' https://www.googletagmanager.com", "https://widget.chat.example",
      "connect-src 'self' https://*.google-analytics.com", "report-uri /csp-reports?surface=website")

    SecurityPolicy.update(mode: "enforce")
    get "/"
    expect(response.headers["Content-Security-Policy"]).to be_present
  end

  it "gives the CMS's inline scripts the nonce when strict, and leaves 'unsafe-inline' out" do
    SecurityPolicy.update(mode: "enforce", strict: "1", presets: %w[google_analytics])
    get "/"
    nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    expect(nonce).to be_present
    expect(response.headers["Content-Security-Policy"]).not_to include("'unsafe-inline' https://www.googletagmanager")
    expect(response.body).to include(%(<script nonce="#{nonce}">gtag("config","G-1")</script>))
  end

  it "is built in Settings › Security policy: what the scripts need, presets, sources, the admin's, and as sent" do
    sign_in_as admin
    get settings_security_policy_path
    expect(response.body).to include("Your scripts need these", "Google Analytics and Google Tag Manager", "https://widget.chat.example", "As sent")

    patch settings_security_policy_path, params: {security_policy: {mode: "report", strict: "0", presets_sent: "1", presets: ["", "google_analytics", "youtube"],
                                                                   sources: {"frame-src" => "https://player.example\nnot a source"},
                                                                   admin_sources: {"form-action" => "https://accounts.google.com"}}}
    policy = SecurityPolicy.get
    expect(policy).to include("mode" => "report", "presets" => %w[google_analytics youtube])
    expect(policy["sources"]).to eq("frame-src" => ["https://player.example"])

    get settings_security_policy_path
    expect(response.headers["Content-Security-Policy"]).to include("form-action 'self' https://accounts.google.com", "report-uri /csp-reports?surface=admin")
  end

  it "takes what browsers report, and allows or dismisses it in a click" do
    post "/csp-reports?surface=admin", params: {"csp-report" => {"document-uri" => "https://acme.test/cms/settings/google", "effective-directive" => "form-action",
                                                                 "blocked-uri" => "https://accounts.google.com/o/oauth2/v2/auth?x=1"}}.to_json,
      headers: {"CONTENT_TYPE" => "application/csp-report"}
    expect(response).to have_http_status(:no_content)
    post "/csp-reports?surface=website", params: [{"type" => "csp-violation", "body" => {"effectiveDirective" => "script-src-elem", "blockedURL" => "https://cdn.example/x.js",
                                                                                         "documentURL" => "https://acme.test/about"}}].to_json,
      headers: {"CONTENT_TYPE" => "application/reports+json"}
    post "/csp-reports?surface=website", params: {"csp-report" => {"effective-directive" => "script-src", "blocked-uri" => "inline"}}.to_json,
      headers: {"CONTENT_TYPE" => "application/csp-report"}
    expect(CspReport.pluck(:surface, :directive, :blocked, :page)).to contain_exactly(%w[admin form-action https://accounts.google.com /cms/settings/google],
      %w[website script-src https://cdn.example /about])

    sign_in_as admin
    get settings_security_policy_path
    expect(response.body).to include("https://cdn.example", "What browsers reported")
    post allow_settings_security_policy_path(CspReport.find_by!(surface: "admin"))
    expect(SecurityPolicy.get["admin_sources"]).to eq("form-action" => ["https://accounts.google.com"])
    delete dismiss_settings_security_policy_path(CspReport.find_by!(surface: "website"))
    expect(CspReport.open).to be_empty
  end

  it "takes settings:write to change it" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[settings:read]))
    get settings_security_policy_path
    expect(response).to have_http_status(:ok)
    patch settings_security_policy_path, params: {security_policy: {mode: "enforce"}}
    expect(SecurityPolicy.mode).to eq("off")
  end
end
