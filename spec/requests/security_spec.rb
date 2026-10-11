# frozen_string_literal: true

require "rails_helper"

# What the security audit closed, one behaviour each.
RSpec.describe "Security", type: :request do
  let(:admin) { create(:user) }
  let(:editor) { create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor))) }

  def bearer(user) = {"Authorization" => "Bearer #{user.api_token.token}"}

  describe "links that would run script" do
    it "aren't stored, through the editor or the API, and aren't drawn" do
      expect(SafeUrl.safe?("https://example.com")).to be(true)
      expect(SafeUrl.safe?("/contact")).to be(true)
      expect(SafeUrl.safe?("#book")).to be(true)
      expect(SafeUrl.safe?("mailto:a@b.test")).to be(true)
      expect(SafeUrl.safe?("javascript:alert(1)")).to be(false)
      expect(SafeUrl.safe?(" JaVa\tScript:alert(1)")).to be(false)
      expect(SafeUrl.safe?("data:text/html,<script>")).to be(false)

      errors = BlockType::Validator.validate_data([{"name" => "cta", "type" => "link"}, {"name" => "site", "type" => "url"}],
        {"cta" => {"kind" => "url", "value" => "javascript:fetch('/cms/users')"}, "site" => "javascript:alert(1)"})
      expect(errors.keys).to include("cta", "site")

      helper = Object.new.extend(WebsiteHelper)
      expect(helper.website_href({"kind" => "url", "value" => "javascript:alert(1)"})).to be_nil
      expect(helper.website_href({"kind" => "url", "value" => "https://example.com"})).to eq("https://example.com")
    end
  end

  describe "the Scripts global" do
    before { Global.create!(slug: "scripts", name: "Scripts", schema: {"fields" => []}, data: {"items" => []}) }

    it "is only for whoever holds globals:scripts, not every editor of globals" do
      sign_in_as editor
      patch global_path("scripts"), params: {global: {name: "Scripts", data: {"items" => [{"head" => "<script>steal()</script>"}]}}}
      expect(Global.find_by!(slug: "scripts").data["items"]).to eq([])

      patch "/api/globals/scripts", params: {global: {data: {"items" => [{"head" => "<script>steal()</script>"}]}}}, headers: bearer(editor), as: :json
      expect(response).to have_http_status(:forbidden)

      patch "/api/globals/scripts", params: {global: {data: {"items" => [{"name" => "GA", "head" => "<script>ga()</script>"}]}}},
        headers: bearer(admin), as: :json
      expect(Global.find_by!(slug: "scripts").data["items"].first["name"]).to eq("GA")
    end
  end

  describe "backups" do
    it "are downloaded by admins only: one holds every account and secret" do
      marketer = create(:user, admin: false, role: create(:role, permissions: %w[tools:use]))

      post "/api/tools/backup", headers: bearer(marketer)
      expect(response).to have_http_status(:forbidden)

      sign_in_as marketer
      post tools_backup_path
      expect(response.media_type).not_to eq("application/gzip")
    end
  end

  describe "settings the CMS keeps itself" do
    it "can't be written over the API, so the signed plugin directory can't be swapped" do
      patch "/api/settings/plugin_directory", params: {setting: {data: {entries: [{key: "evil", repo: "attacker/evil"}]}}},
        headers: bearer(admin), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "masks secrets named as part of a key, and the deploy hook" do
      Setting.set("github", {"github_token" => "ghp_secret1234", "smtp_password" => "pw-9876"})
      Setting.set("deploy", {"url" => "https://api.netlify.com/build_hooks/abcd1234"})

      get "/api/settings/github", headers: bearer(admin)
      expect(response.body).not_to include("ghp_secret1234", "pw-9876")

      get "/api/settings/deploy", headers: bearer(admin)
      expect(response.body).not_to include("build_hooks/abcd")
    end
  end

  describe "direct uploads" do
    let(:blob) { {blob: {filename: "x.png", byte_size: 10, checksum: "abc", content_type: "image/png"}} }

    it "take someone signed in who can add to the library" do
      post "/rails/active_storage/direct_uploads", params: blob, as: :json
      expect(response).to have_http_status(:unauthorized)

      sign_in_as admin
      post "/rails/active_storage/direct_uploads", params: blob, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the API signed in by the browser's session" do
    it "needs the page's CSRF token for a write" do
      Page.create!(slug: "about", title: "About", status: "draft", locale: "en")
      sign_in_as admin
      ActionController::Base.allow_forgery_protection = true

      patch "/api/pages/about", params: {page: {title: "Forged"}}, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(Page.find_by!(slug: "about").title).to eq("About")

      patch "/api/pages/about", params: {page: {title: "By token"}}, headers: bearer(admin), as: :json
      expect(Page.find_by!(slug: "about").title).to eq("By token")
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  describe "the admin's Content-Security-Policy" do
    it "lets scripts run only from the site and with the request's nonce" do
      sign_in_as admin
      get dashboard_path
      policy = response.headers["Content-Security-Policy"]
      expect(policy).to include("script-src 'self'", "'nonce-", "object-src 'none'", "frame-ancestors 'self'")
      expect(policy).not_to include("unsafe-inline' https://challenges", "script-src 'self' 'unsafe-inline'")
    end
  end

  describe "the read-only site token" do
    it "sees only live rows in the sitemap's full list" do
      Page.create!(slug: "secret-plan", title: "Secret plan", status: "draft", locale: "en")
      site = ServiceToken.issue(name: "Site", role: create(:role, permissions: Permissions::SITE_DEFAULT), created_by: nil)

      get "/api/sitemap/entries", headers: {"Authorization" => "Bearer #{site.token}"}
      expect(response.body).not_to include("Secret plan", "secret-plan")
    end
  end

  describe "drafts on the website" do
    it "show to someone signed in who can read content, not to any account" do
      Page.create!(slug: "launch", title: "Launch plan", status: "draft", locale: "en")
      inbox_only = create(:user, admin: false, role: create(:role, permissions: %w[audit_log:read]))
      sign_in_as inbox_only

      get "/launch?preview"
      expect(response.body).not_to include("Launch plan")
    end
  end
end
