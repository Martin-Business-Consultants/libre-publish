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
