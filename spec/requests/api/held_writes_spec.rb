# frozen_string_literal: true

require "rails_helper"

# Cms::Plugins.hold_api_writes: a plugin that's on can hold a token's content
# writes instead of the API applying them (Api::HeldWrites).
RSpec.describe "Held API writes", type: :request do
  let(:admin) { create(:user) }
  let(:token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }
  let(:held) { [] }

  before do
    Cms::Plugins.register :alpha, name: "Alpha", version: "0.1.0", description: "A test plugin.", enabled_by_default: true
    Cms::Plugins.hold_api_writes :alpha, ->(write) { held << write; {status: "held", id: 7} }
  end

  after { forget_plugin(:alpha) }

  it "answers 202 with what the plugin says, and applies nothing" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    patch "/api/pages/about", params: {page: {title: "Changed"}}, headers: token, as: :json

    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)).to eq("status" => "held", "id" => 7)
    expect(page.reload.title).to eq("About")
    expect(held.first).to have_attributes(action: "update", prefix: "pages", attributes: {"title" => "Changed"})
  end

  it "lets a signed-in person's writes through, and every write once the plugin is off" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")
    switch_plugin :alpha, on: false

    patch "/api/pages/about", params: {page: {title: "Changed"}}, headers: token, as: :json

    expect(response).to have_http_status(:ok)
    expect(page.reload.title).to eq("Changed")
    expect(held).to be_empty
  end

  it "refuses the bulk endpoints to a token while writes are held" do
    Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    post "/api/pages/bulk_destroy", params: {slugs: ["about"]}, headers: token, as: :json

    expect(response).to have_http_status(:conflict)
    expect(Page.exists?(slug: "about")).to be(true)
  end
end
