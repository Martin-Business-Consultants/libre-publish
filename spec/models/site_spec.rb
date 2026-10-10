# frozen_string_literal: true

require "rails_helper"

RSpec.describe Site do
  around do |example|
    configured = Rails.configuration.x.app_host
    example.run
  ensure
    Rails.configuration.x.app_host = configured
  end

  it "is reached at APP_HOST when it's set" do
    Rails.configuration.x.app_host = "cms.acme.test"
    Setting.set("general", {"site_base_url" => "https://acme.test"})

    expect(Site.host).to eq("cms.acme.test")
  end

  it "is reached at the site's own address without APP_HOST, since Libre Publish lives on it at /cms" do
    Rails.configuration.x.app_host = nil

    expect(Site.host).to eq("localhost")

    Setting.set("general", {"site_base_url" => "https://acme.test/"})
    expect(Site.host).to eq("acme.test")
    expect(Site.url_options).to include(host: "acme.test")

    Setting.set("general", {"site_base_url" => "http://localhost:3000"})
    expect(Site.host).to eq("localhost:3000")
  end

  it "sends mail with links on that address" do
    Rails.configuration.x.app_host = nil
    Setting.set("general", {"site_base_url" => "https://acme.test"})

    expect(ApplicationMailer.from_address).to eq("noreply@acme.test")
    expect(ApplicationMailer.new.default_url_options).to include(host: "acme.test")
  end
end
