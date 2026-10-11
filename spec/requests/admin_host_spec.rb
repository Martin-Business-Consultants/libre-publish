# frozen_string_literal: true

require "rails_helper"

# CMS_ADMIN_HOST: the admin on a host of its own, the website on the site's.
RSpec.describe "The admin on its own host", type: :request do
  around do |example|
    Rails.configuration.x.admin_host = "cms.example.com"
    Setting.set("general", {"site_base_url" => "https://www.example.com"})
    example.run
  ensure
    Rails.configuration.x.admin_host = nil
  end

  it "serves the admin only there, and sends the website's addresses to the website" do
    host! "www.example.com"
    get "/cms/sign_in"
    expect(response).to redirect_to("http://cms.example.com/cms/sign_in")

    host! "cms.example.com"
    get "/cms/sign_in"
    expect(response).to have_http_status(:ok)

    get "/about?x=1"
    expect(response).to redirect_to("https://www.example.com/about?x=1")
  end

  it "answers the API, files and /up on both" do
    %w[cms.example.com www.example.com].each do |host|
      host! host
      get "/up"
      expect(response).to have_http_status(:ok)
      get "/api/pages"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "links into the admin on its host, from emails" do
    expect(Site.url_options).to include(host: "cms.example.com")
  end

  it "is off without CMS_ADMIN_HOST: one host serves both" do
    Rails.configuration.x.admin_host = nil
    host! "www.example.com"
    get "/cms/sign_in"
    expect(response).to have_http_status(:ok)
  end
end
