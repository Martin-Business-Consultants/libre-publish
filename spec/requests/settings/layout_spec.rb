# frozen_string_literal: true

require "rails_helper"

# Every Settings page, as shadcn/ui's settings layout: its title across the
# top, the sections down the left, the page in the middle and its side cards
# (the Save box, when it has a form) on the right.
RSpec.describe "Settings layout", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "puts the title above the columns, the sections on the left and the Save box beside the page" do
    get settings_general_path

    page = Nokogiri::HTML5(response.body)
    screen = page.at_css(".settings-screen")
    expect(screen.at_css(".settings-screen__header .page-heading")).to be_present
    expect(response.body.index('class="page-heading"')).to be < response.body.index('class="settings-screen__body"')

    nav = screen.at_css(".settings-screen__nav nav[aria-label='Settings sections']")
    expect(nav.at_css("a[aria-current='page']").text).to eq("General")

    expect(screen.at_css(".settings-screen__main form#settings_form")).to be_present
    save = screen.at_css(".settings-screen__aside button[type='submit'][form='settings_form']")
    expect(save.text).to eq("Save changes")

    patch settings_general_path, params: {settings: {title: "Acme"}}
    expect(Setting.get("general")["title"]).to eq("Acme")
  end

  it "leaves out the side column on a page without one" do
    get settings_service_tokens_path

    expect(response.body).to include('aria-label="Settings sections"')
    expect(response.body).not_to include("settings-screen__aside")
  end

  it "shows what an API token can do as items" do
    get settings_api_token_path

    items = Nokogiri::HTML5(response.body).css(".settings-grid .ui-item")
    expect(items).not_to be_empty
    expect(response.body).to include('aria-label="Settings sections"')
  end
end
