# frozen_string_literal: true

require "rails_helper"

# Every Settings page, as Runwell's: its title in the panel bar, the Settings
# nav down the left, the page beside it in pill tabs where it has several
# sections, and its Save bar (when it has a form) at the page's foot.
RSpec.describe "Settings layout", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "puts the title in the panel bar, the nav beside the page, and the Save bar under it" do
    get settings_general_path

    body = response.body
    expect(body[%r{<nav class="crumbs".*?</nav>}m]).to include("General")
    nav = body[%r{<nav class="settings-nav".*?</nav>}m]
    expect(nav).to include("General", %(href="#{settings_general_path}"), 'aria-current="page"', "All plugins")
    page = body[%r{<div class="settings-layout__page">.*}m]
    expect(page).to include('data-controller="tabs"', 'data-tab="serving"', 'id="settings_form"')
    expect(page[%r{<div class="settings-save">.*?</div>}m]).to include('form="settings_form"', "Save changes")

    patch settings_general_path, params: {settings: {title: "Acme"}}
    expect(Setting.get("general")["title"]).to eq("Acme")
  end

  it "shows what an API token can do as cards" do
    get settings_api_token_path

    cards = Nokogiri::HTML5(response.body).css(".settings-cards .settings-cards__card")
    expect(cards).not_to be_empty
    expect(response.body).to include('class="settings-nav"')
  end
end
