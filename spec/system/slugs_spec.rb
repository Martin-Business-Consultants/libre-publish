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

  # The page's JavaScript loads as modules after the page: wait for its controllers before
  # using them, or a click lands before anything listens for it.
  def wait_for_controllers(*identifiers)
    script = "!!window.Stimulus && #{identifiers.to_json}.every(id => window.Stimulus.controllers.some(c => c.identifier === id))"
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 until page.evaluate_script(script) || Time.now > deadline
  end

  # Types into a field and waits until what's typed has stuck and the slug shows it: now and
  # then the sheet's first keystrokes land while the page is still settling and are lost, so
  # it types again rather than failing on a race the person using it never sees.
  def type_title(field, text, slug_field:, slug:)
    page.document.synchronize do
      fill_in field, with: text
      raise Capybara::ExpectationNotMet, "#{slug_field} is #{find_field(slug_field).value.inspect}, #{field} is #{find_field(field).value.inspect}" unless find_field(slug_field).value == slug
    end
  end

  it "fills a new page's slug from its title, until someone types their own" do
    visit pages_path
    wait_for_controllers "dialog", "slug"
    click_on "New page"

    within "dialog[open]" do
      type_title "page[title]", "Our Café & Bar", slug_field: "page[slug]", slug: "our-cafe-bar"
      expect(page).to have_field("page[slug]", with: "our-cafe-bar")

      fill_in "page[slug]", with: "visit"
      fill_in "page[title]", with: "Our Café & Bar, Downtown"
      expect(page).to have_field("page[slug]", with: "visit")
    end
  end

  it "uses underscores for a global, starting with a letter" do
    visit globals_path
    wait_for_controllers "dialog", "slug"
    click_on "New global"

    within "dialog[open]" do
      type_title "global[name]", "2026 Site Settings", slug_field: "global[slug]", slug: "site_settings"
      expect(page).to have_field("global[slug]", with: "site_settings")
    end
  end

  it "leaves a saved page's slug alone when its title changes" do
    saved = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")

    visit edit_page_path(saved.path)
    wait_for_controllers "slug"
    fill_in "page[title]", with: "About the bakery"

    expect(page).to have_field("page[slug]", with: "about")
  end
end
