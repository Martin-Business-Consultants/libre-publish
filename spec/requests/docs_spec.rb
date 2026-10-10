# frozen_string_literal: true

require "rails_helper"

# Docs: the guides (app/guides), written for this install, and site health,
# checked against the site — in the admin, the API and the CLI.
RSpec.describe "Docs", type: :request do
  let(:admin) { create(:user) }

  def api_headers = {"Authorization" => "Bearer #{admin.api_token.token}"}

  it "lists the guides and shows one, filled in for this CMS" do
    sign_in_as admin

    get docs_path
    expect(response.body).to include("How this CMS works", "Working with an Astro site", "Working with AI", "Site health")

    get doc_path("astro")
    expect(CGI.unescapeHTML(response.body)).to include("curl -fsSL http://www.example.com/frontend/install.sh | sh", ">cms docs astro</code>")
    expect(response.body).not_to include("{{cms_url}}")

    get doc_path("nope")
    expect(response).to have_http_status(:not_found)
  end

  it "serves the guides to the CLI and MCP" do
    get "/api/docs", headers: api_headers
    expect(response.parsed_body["guides"].map { it["slug"] }).to eq(%w[how-it-works astro ai])

    get "/api/docs/ai", headers: api_headers
    expect(response.parsed_body.dig("guide", "markdown")).to include("claude mcp add cms -- cms mcp")

    get "/api/go_live", headers: api_headers
    expect(response).to have_http_status(:not_found)
  end

  it "shows site health in Docs, the API and the CLI" do
    sign_in_as admin

    get site_health_docs_path
    expect(CGI.unescapeHTML(response.body)).to include("Site health", "One phone number, everywhere", "cms site-health")

    get "/api/site_health", headers: api_headers
    expect(response.parsed_body["checks"].map { it["key"] }).to include("phone_consistent", "privacy_page", "recent_backup")
  end
end
