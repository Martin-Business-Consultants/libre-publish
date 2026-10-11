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
    unmarked = response.body.gsub(/\u2063[\u200B\u200C\u200D\u2060]*\u2063|\u2064/, "")
    expect(unmarked).to include("<h1>About us</h1>", "Unsaved <strong>words</strong>")
    expect(page.reload).to have_attributes(title: "About", lock_version: 0)
  end

  it "offers the tab only when a theme draws the site" do
    get edit_page_path(page.path)
    expect(response.body).to include(%(data-tab="preview"), "website-preview")
  end

  it "marks the title and the blocks' short text for editing in place, and loads the script that does it" do
    BlockType::Defaults.install!
    patch page_path(page.path, website_preview: 1), params: edit_params(title: "About us", body: "Unsaved words")

    expect(response.body).to include("\u2063", "About us\u2064", "inline_edit")
    fields = JSON.parse(Nokogiri::HTML(response.body).at("#lp-inline-edit").text)["fields"]
    expect(fields).to include("title")
    expect(page.reload.title).to eq("About")
  end

  # Replace and Crop & edit (inline_edit.js): the <img> a block's image field
  # draws says which field it is; the same image elsewhere doesn't.
  it "names a block's image field on the <img> the theme draws for it" do
    asset = Asset.create!(folder: "/", file: {io: File.open(Rails.root.join("public/icon.png")), filename: "icon.png", content_type: "image/png"})
    blocks = {
      "0" => {"_json" => {"type" => "text", "version" => 1, "data" => {"body" => "Words"}}.to_json},
      "1" => {"_json" => {"type" => "media_text", "version" => 1, "data" => {"image_id" => asset.id.to_s}}.to_json}
    }
    patch page_path(page.path, website_preview: 1), params: {page: {title: "About", slug: "about", status: "published", lock_version: page.lock_version, blocks: blocks}}

    image = Nokogiri::HTML(response.body).at("figure.media-text img")
    expect(image["data-lp-image"]).to eq("blocks.1.image_id")

    get "/about"
    expect(response.body).not_to include("data-lp-image")
  end

  describe "the image editor" do
    let!(:asset) do
      Asset.create!(folder: "/photos", name: "Garden", alt: "A garden bed", file: {io: File.open(Rails.root.join("public/icon.png")), filename: "garden.png", content_type: "image/png"})
    end

    it "is in the preview, and hands out the image to edit" do
      get edit_page_path(page.path)
      expect(response.body).to include(%(data-controller="image-editor"))

      get file_manager_asset_image_edit_path(asset), as: :json
      expect(response.parsed_body).to include("name" => "Garden", "url" => a_string_including("garden.png"))
    end

    it "saves the edit as a copy beside the original, keeping its text, and leaves the original as it was" do
      edited = Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png", original_filename: "garden-edited.png")

      expect { post file_manager_asset_image_edit_path(asset), params: {image: edited} }.to change(Asset, :count).by(1)

      expect(response).to have_http_status(:created)
      copy = Asset.find(response.parsed_body["id"])
      expect(copy).to have_attributes(folder: "/photos", name: "Garden (edited)", alt: "A garden bed")
      expect(response.parsed_body["thumb"]).to include("<img")
      expect(asset.reload.filename.to_s).to eq("garden.png")
    end

    it "refuses something that isn't an image" do
      text = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "notes.txt")
      post file_manager_asset_image_edit_path(asset), params: {image: text}
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
