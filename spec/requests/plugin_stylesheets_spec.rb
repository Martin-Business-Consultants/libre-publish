# frozen_string_literal: true

require "rails_helper"

# A plugin's stylesheet loads only where the plugin shows something
# (ApplicationHelper#page_plugins), and one production can't find is left
# out rather than failing the page (it took /pages down in 1.5.x).
RSpec.describe "Plugins' stylesheets", type: :request do
  before do
    sign_in_as create(:user)
    switch_plugin :hello, on: true
  end

  it "loads a plugin's own stylesheet on its own pages, not the others" do
    get hello_greetings_path
    expect(response.body).to include("hello/hello")

    get pages_path
    expect(response.body).not_to include("hello/hello")
  end

  it "knows a plugin's page by its engine when its controller isn't gated" do
    expect(Cms::Plugins.owner_of(Hello::GreetingsController)).to eq(:hello)
    expect(Cms::Plugins.owner_of(PagesController)).to be_nil
  end

  it "loads it where one of its slots renders" do
    get dashboard_path # Hello's dashboard panel

    expect(response.body).to include("hello/hello")
  end

  context "for a plugin whose stylesheet can't be found" do
    before do
      Cms::Plugins.register :sketchy, name: "Sketchy", version: "0.1.0", description: "A test plugin.", enabled_by_default: true
      Cms::Plugins.stylesheet :sketchy, "sketchy/not_compiled"
      Cms::Plugins.slot :nav_actions, :sketchy, "layouts/shared/logo"
      allow(Rails.error).to receive(:report)
    end

    after { forget_plugin(:sketchy) }

    it "leaves it out of the page, which still renders, and reports it" do
      get pages_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("sketchy/not_compiled")
      expect(Rails.error).to have_received(:report).with(an_instance_of(Propshaft::MissingAssetError), hash_including(handled: true))
    end
  end
end
