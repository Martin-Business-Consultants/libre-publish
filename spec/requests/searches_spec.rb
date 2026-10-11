# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Searching everything from the admin bar", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "is a search icon in the admin bar" do
    get dashboard_path

    expect(response.body).to include(%(href="#{search_path}"), "Search everything")
  end

  it "lists what holds the term, each linking to where it's edited, with where it matched" do
    page = Page.create!(slug: "pricing", title: "Pricing", status: "draft", locale: "en")
    Role.create!(name: "Pricing desk", permissions: %w[pages:read])

    get search_path(q: "pricing")

    expect(response.body).to include(%(href="#{edit_page_path(page.path)}"), "Pricing desk", "<mark>")
    expect(response.body).to include("Page", "Role")
  end

  it "opens a modal that finds titles fuzzily as you type, then text that holds the term" do
    get dashboard_path
    expect(response.body).to include("data-global-search-open", %(data-controller="global-search"))

    page = Page.create!(slug: "home", title: "Home page", status: "draft", locale: "en")
    Page.create!(slug: "contact", title: "Contact", status: "draft", locale: "en",
      seo: {"description" => "Reach the homestead team"})

    get search_path(q: "hmpg", quick: 1)
    expect(response.body).not_to include("<html")
    expect(response.body).to include(%(href="#{edit_page_path(page.path)}"), "<mark>H</mark>", "Titles")

    get search_path(q: "h", quick: 1)
    expect(response.body).to include("<mark>H</mark>ome page")

    get search_path(q: "zzqx", quick: 1)
    expect(response.body).to include("Nothing matches")
  end

  it "ranks the term whole, and at a word's start, over letters strewn about" do
    whole, = GlobalSearch::Quick.match("page", "Home page")
    strewn, = GlobalSearch::Quick.match("page", "Plain language")
    expect(whole).to be > strewn
    expect(GlobalSearch::Quick.match("hmpg", "Home page").last).to eq([0, 2, 5, 7])
    expect(GlobalSearch::Quick.match("xyz", "Home page")).to be_nil
  end

  it "pages through many" do
    30.times { |n| Redirect.create!(source_path: "/sale-#{n}", destination_url: "/sale", status_code: 301) }

    get search_path(q: "sale")

    expect(response.body).to include("1–25", "of 30", %(href="#{ERB::Util.h(search_path(q: "sale", page: 2))}"))
  end

  it "asks for more than two characters, and nothing for no term" do
    get search_path(q: "ab")
    expect(response.body).to include("Type at least 3 characters")

    get search_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Type at least")
  end
end
