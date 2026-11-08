# frozen_string_literal: true

require "rails_helper"

# The guides (app/guides), written for this install, and site health,
# checked against the site, for the CLI and MCP.
RSpec.describe "Docs", type: :request do
  let(:admin) { create(:user) }

  def api_headers = {"Authorization" => "Bearer #{admin.api_token.token}"}

  it "serves the guides to the CLI and MCP" do
    get "/api/docs", headers: api_headers
    expect(response.parsed_body["guides"].map { it["slug"] }).to eq(%w[how-it-works ai])

    get "/api/docs/ai", headers: api_headers
    expect(response.parsed_body.dig("guide", "markdown")).to include("cms connect")

    get "/api/go_live", headers: api_headers
    expect(response).to have_http_status(:not_found)
  end

  it "serves site health to the CLI" do
    get "/api/site_health", headers: api_headers
    expect(response.parsed_body["checks"].map { it["key"] }).to include("phone_consistent", "privacy_page", "recent_backup")
  end
end
