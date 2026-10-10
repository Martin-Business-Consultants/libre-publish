# frozen_string_literal: true

require "rails_helper"

# What makes the CMS's headlessness evident, and what a frontend reads: the
# editors' JSON tab (the API's own JSON), the Developers screen, the site
# repo's AGENTS.md, and a build reporting in.
RSpec.describe "Headless", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user = admin) = {"Authorization" => "Bearer #{user.api_token.token}"}

  it "shows a page, an entry and a global in their editors' JSON tab exactly as the API returns them" do
    sign_in_as admin
    page = Page.create!(slug: "about", title: "About us", status: "published", locale: "en", frontmatter: {"lede" => "Hi"})

    get edit_page_path(page.path)
    expect(response.body).to include('data-controller="tabs"', api_preview_path("page", page.id))

    get api_preview_path("page", page.id)
    preview = response.body[%r{<pre class="api-json__body [^"]*"><code>(.*)</code></pre>}m, 1]
    get "/api/pages/about", params: {resolve: "assets"}, headers: api_headers
    expect(JSON.parse(CGI.unescapeHTML(preview))).to eq(response.parsed_body)

    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    entry = collection.entries.create!(slug: "hello", title: "Hello", status: "draft", locale: "en")
    get api_preview_path("entry", entry.id)
    expect(response.body).to include("/api/collections/posts/entries/hello", "cms.entry(&quot;posts&quot;, &quot;hello&quot;)")

    global = Global.create!(slug: "footer", name: "Footer", schema: {"fields" => []}, data: {})
    get api_preview_path("global", global.id)
    expect(response.body).to include("/api/globals/footer", "cms.global(&quot;footer&quot;)")
  end

  it "keeps the JSON from a role that can't read the record" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[entries:read]))
    page = Page.create!(slug: "secret", title: "Secret", status: "draft", locale: "en")

    get api_preview_path("page", page.id)
    expect(response).to have_http_status(:forbidden)
  end

  it "explains the headless setup on the Developers screen, with the frontend's last build" do
    sign_in_as admin
    get developers_path
    expect(response.body).to include("/api/v1/pages/:path", "@librepublish/astro", "cms()", "No build has reported yet")

    post "/api/frontend/builds", params: {integration: "librepublish-cms", integration_version: "1.0.0",
      framework: "astro", framework_version: "5.1.0", pages: 42}, headers: api_headers, as: :json
    expect(response).to have_http_status(:ok)

    get developers_path
    expect(response.body).to include("astro 5.1.0", "librepublish-cms 1.0.0", "42")
    get dashboard_path
    expect(response.body).to include("Your frontend", "42 pages")
  end

  it "serves the site repo's AGENTS.md, filled in for this CMS" do
    get "/frontend/AGENTS.md"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/markdown")
    expect(response.body).to start_with("# This site is the frontend of a headless CMS")
    expect(response.body).to include("http://www.example.com/api/v1/content", "@librepublish/astro/loaders", "Site health")
    expect(response.body).not_to include("__CMS_URL__", "librepublish:cms-frontend")
  end

  it "serves the Astro installer, which installs the integration rather than copying files" do
    get "/frontend/install.sh"
    expect(response.body).to include("http://www.example.com", "@librepublish/astro", "github:Martin-Business-Consultants/libre-cms-astro", "purpose=site", "/api/v1/site")
    expect(response.body).not_to include("__CMS_URL__", "/frontend/files/")

    get "/frontend/files/integration.ts"
    expect(response).to have_http_status(:not_found)
  end

  it "gives an approved site its own read-only service token, and only someone who may issue one can approve it" do
    SiteBootstrap.bootstrap!(site_name: "Acme")
    post "/api/device/code", params: {purpose: "site", label: "acme-site", hostname: "laptop"}
    code = response.parsed_body

    editor = create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))
    sign_in_as editor
    post connect_path, params: {code: code["user_code"], decision: "approve"}
    expect(DeviceAuthorization.find_by(user_code: code["user_code"])).not_to be_approved

    sign_in_as admin
    get connect_path(code: code["user_code"])
    expect(response.body).to include("acme-site", "read-only token of its own")
    post connect_path, params: {code: code["user_code"], decision: "approve"}

    post "/api/device/token", params: {device_code: code["device_code"]}
    body = response.parsed_body
    expect(body).to include("purpose" => "site", "token_name" => "acme-site")
    token = ServiceToken.find_by!(name: "acme-site")
    expect(token.role.name).to eq("Production site")
    expect(ServiceToken.authenticate(body["token"])).to eq(token)
  end

  it "names each screen's cms command under its title, and lists recent API use on the dashboard" do
    sign_in_as admin
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    get edit_page_path(page.path)
    expect(response.body).to include("From the CLI or MCP", ">cms page about</code>")
    get tools_redirects_path
    expect(response.body).to include(">cms redirects</code>")

    admin.api_token.update_columns(last_used_at: 1.hour.ago)
    get dashboard_path
    expect(response.body).to include("Working through the API", admin.name, "CLI, MCP or API")
  end

  it "tells the CLI about the frontend" do
    get "/api/frontend", headers: api_headers
    expect(response.parsed_body.dig("frontend", "connect", "install")).to eq("curl -fsSL http://www.example.com/frontend/install.sh | sh")
  end
end
