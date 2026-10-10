# frozen_string_literal: true

require "rails_helper"

# The editor's Preview tab posts the form, unsaved, to the record's own
# address with ?website_preview; the theme draws what was posted.
RSpec.describe "Previewing an edit on the website", type: :request do
  let(:admin) { create(:user) }
  let(:page) do
    Page.create!(slug: "about", title: "About", status: "published", locale: "en",
      blocks: [{"type" => "text", "version" => 1, "data" => {"body" => "Saved words"}}])
  end

  before do
    BlockType::Defaults.install!
    page
    sign_in_as admin
  end

  around do |example|
    registered = Website.theme
    Website.register :fixture, name: "Fixture", version: "1", views: Rails.root.join("spec/fixtures/website_theme/views")
    example.run
  ensure
    Website.theme = registered
    Website.themes.delete("fixture")
  end

  def edit_params(title:, body:)
    {page: {title: title, slug: "about", status: "published", lock_version: page.lock_version,
            blocks: {"0" => {"_json" => {"type" => "text", "version" => 1, "data" => {"body" => body}}.to_json}}}}
  end

  it "draws the page as edited, through the theme, without saving it" do
    patch page_path(page.path, website_preview: 1), params: edit_params(title: "About us", body: "Unsaved **words**")

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to include("<h1>About us</h1>", "Unsaved <strong>words</strong>")
    expect(page.reload).to have_attributes(title: "About", lock_version: 0)
  end

  it "offers the tab only when a theme draws the site" do
    get edit_page_path(page.path)
    expect(response.body).to include(%(data-tab="preview"), "website-preview")
  end
end
