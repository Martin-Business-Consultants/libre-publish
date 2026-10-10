# frozen_string_literal: true

require "rails_helper"

# A webhook's settings and delivery log, rendered with real data.
RSpec.describe "Webhook pages", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "renders a webhook's edit and show pages with deliveries" do
    webhook = Webhook.create!(name: "Astro", url: "https://e.test/hook", events: ["page.published"], headers: {"X-A" => "1"})
    webhook.deliveries.create!(event: "page.published", payload: "{}", success: false, response_status: 500, duration_ms: 12, error: "boom")

    get edit_webhook_path(webhook)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("Signing secret", "X-A: 1", "boom", "Send a test")

    get webhook_path(webhook)
    expect(response).to have_http_status(:success)
    expect(response.body).to include("https://e.test/hook", "boom")
  end
end
