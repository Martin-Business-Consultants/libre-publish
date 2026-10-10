# frozen_string_literal: true

require "rails_helper"

# The slug controller: a slug fills in from the title as it's typed, until
# someone types their own, and a saved record's never follows its title.
RSpec.describe "Slugs from titles", type: :system do
  let(:admin) { create(:user, password: "password1234") }

  before do
    visit sign_in_path
    find("input[type=email]").fill_in(with: admin.email)
    find("input[type=password]").fill_in(with: "password1234")
    find("button[type=submit]").click
    expect(page).to have_css("#admin-menu")
  end

  it "fills a new page's slug from its title, until someone types their own" do
    visit pages_path
    click_on "New page"

    within "dialog[open]" do
      fill_in "page[title]", with: "Our Café & Bar"
      expect(find_field("page[slug]").value).to eq("our-cafe-bar")

      fill_in "page[slug]", with: "visit"
      fill_in "page[title]", with: "Our Café & Bar, Downtown"
      expect(find_field("page[slug]").value).to eq("visit")
    end
  end

  it "uses underscores for a global, starting with a letter" do
    visit globals_path
    click_on "New global"

    within "dialog[open]" do
      fill_in "global[name]", with: "2026 Site Settings"
      expect(find_field("global[slug]").value).to eq("site_settings")
    end
  end

  it "leaves a saved page's slug alone when its title changes" do
    saved = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    visit edit_page_path(saved.path)
    fill_in "page[title]", with: "About the bakery"

    expect(find_field("page[slug]").value).to eq("about")
  end
end
