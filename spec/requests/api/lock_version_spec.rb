# frozen_string_literal: true

require "rails_helper"

# Optimistic locking (Api::LockVersioned, ContentEditing): a write that says
# which version it read is refused when someone saved since; one that
# doesn't say is applied as it always was.
RSpec.describe "Writes over someone else's change", type: :request do
  let(:admin) { create(:user) }
  let(:token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }
  let!(:page) { Page.create!(slug: "about", title: "About", status: "draft", locale: "en") }

  describe "through the API" do
    it "says which version it read, on reads and writes" do
      get "/api/pages/about", headers: token

      expect(response.headers["X-Lock-Version"]).to eq(page.lock_version.to_s)
      expect(JSON.parse(response.body)["page"]).not_to have_key("lock_version")
    end

    it "applies a write made from the latest version, and says the new one" do
      patch "/api/pages/about", params: {page: {title: "Ours", lock_version: page.lock_version}}, headers: token, as: :json

      expect(response).to have_http_status(:ok)
      expect(page.reload.title).to eq("Ours")
      expect(response.headers["X-Lock-Version"]).to eq(page.lock_version.to_s)
    end

    it "refuses a write made from an older version, and leaves theirs" do
      read = page.lock_version
      page.update!(title: "Theirs")

      patch "/api/pages/about", params: {page: {title: "Ours", lock_version: read}}, headers: token, as: :json

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)).to include("error" => "conflict", "lock_version" => page.reload.lock_version)
      expect(page.title).to eq("Theirs")
    end

    it "applies a write that doesn't say, as before" do
      page.update!(title: "Theirs")

      patch "/api/pages/about", params: {page: {title: "Ours"}}, headers: token, as: :json

      expect(response).to have_http_status(:ok)
      expect(page.reload.title).to eq("Ours")
    end

    it "does the same for entries and globals" do
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      entry = collection.entries.create!(slug: "hello", title: "Hello", status: "draft", locale: "en")
      global = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})
      entry.update!(title: "Theirs")
      global.update!(name: "Theirs")

      patch "/api/collections/posts/entries/hello", params: {entry: {title: "Ours", lock_version: 0}}, headers: token, as: :json
      expect(response).to have_http_status(:conflict)

      patch "/api/globals/footer", params: {global: {name: "Ours", lock_version: 0}}, headers: token, as: :json
      expect(response).to have_http_status(:conflict)
      expect([entry.reload.title, global.reload.name]).to eq(%w[Theirs Theirs])
    end

    it "refuses a version that isn't a number" do
      patch "/api/pages/about", params: {page: {title: "Ours", lock_version: "latest"}}, headers: token, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(page.reload.title).to eq("About")
    end
  end

  describe "in the admin" do
    before { sign_in_as admin }

    it "keeps the form and says so when someone saved since it was opened" do
      read = page.lock_version
      page.update!(title: "Theirs")

      patch page_path("about"), params: {page: {title: "Ours", lock_version: read}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Someone else saved this while you were editing")
      expect(page.reload.title).to eq("Theirs")
    end

    it "saves a form opened from the latest version" do
      patch page_path("about"), params: {page: {title: "Ours", lock_version: page.lock_version}}

      expect(response).to have_http_status(:redirect)
      expect(page.reload.title).to eq("Ours")
    end
  end
end
