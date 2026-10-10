# frozen_string_literal: true

require "rails_helper"

# A service token authenticates the API the same way a personal one does, and
# is bounded by its own role instead of a person's.
RSpec.describe "Service token auth", type: :request do
  SERVICE_SUBDOMAIN = "servicetok"

  before do
    SiteSetup.new(
      name: "Service Token Spec",
      owner_email: "owner@#{SERVICE_SUBDOMAIN}.example.com"
    ).call
  end

  def issue(role_name)
    role = Role.find_by!(name: role_name)
    existing = ServiceToken.active.find_by(name: role_name)
    token = existing || ServiceToken.issue!(name: role_name, role: role)
    {"Authorization" => "Bearer #{token.rotate!}"}
  end

  def make_page(**attrs)
    Page.create!({
      slug: "p-#{SecureRandom.hex(4)}", title: "Live", status: "published",
      locale: "en", blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {}
    }.merge(attrs))
  end

  it "provisioning issues both machine tokens" do
    names = ServiceToken.active.pluck(:name)
    expect(names).to include("Production site", "Agent")
  end

  describe "the production token" do
    it "reads content" do
      make_page

      get "/api/pages", headers: issue("Production site")

      expect(response).to have_http_status(:success)
    end

    it "never sees a draft, in a list or by its path" do
      make_page(slug: "live", title: "Live")
      draft = make_page(slug: "draft", title: "Draft", status: "draft")
      collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
      collection.entries.create!(slug: "hidden", title: "Hidden", status: "draft")

      get "/api/pages", headers: issue("Production site")
      expect(JSON.parse(response.body)["pages"].map { it["slug"] }).to eq(["live"])

      get "/api/pages/#{draft.path}", headers: issue("Production site")
      expect(response).to have_http_status(:not_found)

      get "/api/collections/posts/entries", headers: issue("Production site")
      expect(JSON.parse(response.body)["entries"]).to be_empty
      get "/api/collections/posts/entries/hidden", headers: issue("Production site")
      expect(response).to have_http_status(:not_found)
    end

    it "can't write — a leaked site secret reads what the site already shows" do
      page = make_page(title: "Live")

      patch "/api/pages/#{page.path}", params: {page: {title: "Hacked"}},
        headers: issue("Production site"), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["capability"]).to eq("pages:write")
      expect(page.reload.title).to eq("Live")
    end

    it "identifies itself by name, having no user behind it" do
      get "/api/api_tokens/me", headers: issue("Production site")

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["service"]).to include("name" => "Production site", "role" => "Production site")
      expect(body["user"]).to be_nil
    end
  end

  describe "the agent token" do
    it "can't change live content: a 403, and the page stays as it was" do
      page = make_page(title: "Live")

      patch "/api/pages/#{page.path}", params: {page: {title: "Changed"}},
        headers: issue("Agent"), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(page.reload.title).to eq("Live")
    end

    it "can't publish a draft" do
      page = make_page(status: "draft", title: "Draft")

      patch "/api/pages/#{page.path}", params: {page: {status: "published"}},
        headers: issue("Agent"), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(page.reload.status).to eq("draft")
    end

    it "writes a draft directly — nobody is looking at it" do
      page = make_page(status: "draft", title: "Draft")

      patch "/api/pages/#{page.path}", params: {page: {title: "Edited"}},
        headers: issue("Agent"), as: :json

      expect(response).to have_http_status(:success)
      expect(page.reload.title).to eq("Edited")
    end
  end

  describe "revocation" do
    it "stops the token at the door" do
      headers = issue("Production site")
      ServiceToken.active.find_by!(name: "Production site").revoke!

      get "/api/pages", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
