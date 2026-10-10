# frozen_string_literal: true

require "rails_helper"

# Libre Publish lives under /cms, and /cms is a signpost, not a page of its
# own: it bounces to wherever the person should start. That's Pages — the
# content is the point of the CMS, and every human role holds `pages:read`.
# "/" is the website's; a headless install, with no site, sends it to /cms.
RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }

  it "lives under /cms" do
    expect(cms_path).to eq("/cms")
    expect(pages_path).to eq("/cms/pages")
    expect(sign_in_path).to eq("/cms/sign_in")
    expect(api_v1_site_path).to eq("/api/v1/site")
  end

  describe "GET /cms" do
    it "sends a signed-in user to pages" do
      post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}

      get cms_url
      expect(response).to redirect_to(pages_url)
    end

    it "sends a signed-out visitor to sign in" do
      get cms_url
      expect(response).to redirect_to(sign_in_url)
    end
  end

  describe "an address the admin had before /cms" do
    it "goes there, query and all" do
      get "/pages/home/edit?tab=seo"
      expect(response).to redirect_to("/cms/pages/home/edit?tab=seo")
      expect(response).to have_http_status(:moved_permanently)

      get "/no-such-thing"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "sends / to /cms on a headless install" do
    get root_url
    expect(response).to redirect_to("/cms")
  end
end
