# frozen_string_literal: true

require "rails_helper"

# Every Settings page: its title across the top, the page in two thirds, and
# a sidebar with its Save box (when it has a form) and the sections.
RSpec.describe "Settings layout", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "puts the title above the columns, and the Save box and sections in the sidebar" do
    get settings_general_path

    body = response.body
    columns = body.index('class="settings-columns ')
    expect(body.index('class="page-title ')).to be < columns
    aside = body[%r{<aside class="settings-aside .*?</aside>}m]
    expect(aside).to include('form="settings_form"', "Save changes", 'aria-label="Settings sections"', 'aria-current="page"')
    expect(body).to include('id="settings_form"')

    patch settings_general_path, params: {settings: {title: "Acme"}}
    expect(Setting.get("general")["title"]).to eq("Acme")
  end

  it "shows what an API token can do as cards" do
    get settings_api_token_path

    cards = Nokogiri::HTML5(response.body).css(".settings-cards .settings-cards__card")
    expect(cards).not_to be_empty
    expect(response.body).to include('aria-label="Settings sections"')
  end
end
