# frozen_string_literal: true

require "rails_helper"

# The site's build reporting itself (POST /api/frontend/builds), and what
# Settings › Deploy makes of it: how the site renders, where purges go, the
# secret they're signed with.
RSpec.describe "Frontend builds", type: :request do
  let(:admin) { create(:user) }
  let(:site_token) { {"Authorization" => "Bearer #{create(:user, admin: false, role: create(:role, permissions: %w[pages:read])).api_token.token}"} }

  let(:admin_token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }
  let(:on_demand) { {render: "server", webhook_url: "https://acme.test/_cms/webhook"} }

  it "keeps what the site reports, and the content it was built from" do
    post "/api/frontend/builds", params: {integration: "@librepublish/astro", integration_version: "1.0.0", framework: "astro",
      framework_version: "7.0.0", pages: 12, render: "static", content_cursor: "c-2026-10-06T12:00:00Z-41"}, headers: site_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["build"]).to include("render" => "static", "content_cursor" => "c-2026-10-06T12:00:00Z-41")
    expect(Frontend.render).to eq("static")
    expect(Frontend.prerendered?).to be(true)
  end

  it "won't let the site's read-only token switch publishing to purges, or say where they go" do
    post "/api/frontend/builds", params: on_demand, headers: site_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["pending_delivery"]).to eq("render" => "server", "webhook_url" => "https://acme.test/_cms/webhook")
    expect(Frontend.purges?).to be(false)
    expect(Frontend.prerendered?).to be(true)
  end

  it "takes it once someone who can change Settings › Deploy approves it" do
    post "/api/frontend/builds", params: on_demand, headers: site_token, as: :json

    post "/api/frontend/delivery_approval", headers: site_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/frontend/delivery_approval", headers: admin_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("approved" => true)
    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")
    expect(Frontend.prerendered?).to be(false)
    expect(AuditLog.last.action).to eq("frontend.delivery_approved")

    post "/api/frontend/delivery_approval", headers: admin_token, as: :json
    expect(JSON.parse(response.body)).to include("approved" => false)
  end

  it "takes it straight away from a token that can change Settings › Deploy" do
    post "/api/frontend/builds", params: on_demand, headers: admin_token, as: :json

    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")
  end

  it "keeps purges where they were approved when a later report moves them, or turns them off" do
    Frontend.record_build(on_demand.stringify_keys)
    Frontend.approve_delivery!

    post "/api/frontend/builds", params: {render: "server", webhook_url: "https://evil.test/hook"}, headers: site_token, as: :json
    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")

    post "/api/frontend/builds", params: {render: "static"}, headers: site_token, as: :json
    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")
    expect(Frontend.pending_delivery).to eq("render" => "static")
  end

  it "keeps what an install upgraded from before approvals had" do
    Setting.set(Frontend::SETTING, {"last_build" => {"render" => "server", "webhook_url" => "https://acme.test/_cms/webhook",
      "built_at" => Time.current.iso8601}})
    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")

    post "/api/frontend/builds", params: {render: "server", webhook_url: "https://evil.test/hook"}, headers: site_token, as: :json
    expect(Frontend.purge_url).to eq("https://acme.test/_cms/webhook")
  end

  it "drops what it doesn't understand rather than refusing the report" do
    post "/api/frontend/builds", params: {render: "edge", webhook_url: "javascript:alert(1)"}, headers: site_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Frontend.render).to be_nil
    expect(Frontend.purges?).to be(false)
    expect(Frontend.prerendered?).to be(true)
  end

  it "shows it in Settings › Deploy, waiting for approval, then with the purge secret to reveal and rotate" do
    Frontend.record_build("render" => "server", "webhook_url" => "https://acme.test/_cms/webhook", "integration" => "@librepublish/astro",
      "content_cursor" => "abc123")
    sign_in_as admin

    get settings_deploy_path
    expect(response.body).to include("waits for approval", "Approve")
    expect(response.body).not_to include("CMS_WEBHOOK_SECRET")

    post settings_deploy_delivery_approval_path
    expect(Frontend.purges?).to be(true)

    get settings_deploy_path
    expect(response.body).to include("renders on demand", "https://acme.test/_cms/webhook", "abc123", "CMS_WEBHOOK_SECRET")
    expect(response.body).not_to include(Frontend.purge_secret)

    post settings_deploy_purge_secret_reveal_path
    old = Frontend.purge_secret
    expect(response.body).to include(old)
    expect(AuditLog.last.action).to eq("settings.purge_secret_revealed")

    post settings_deploy_purge_secret_rotation_path
    expect(Frontend.purge_secret).not_to eq(old)
  end

  it "says a static site is rebuilt" do
    Frontend.record_build("render" => "static")
    sign_in_as admin

    get settings_deploy_path
    expect(response.body).to include("renders statically, so publishing rebuilds it")
  end
end
