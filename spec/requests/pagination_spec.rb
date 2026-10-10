# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Index tables' numbered pagination", type: :request do
  let(:admin) { create(:user) }

  # The pagination under the table.
  def nav = response.body[%r{<nav class="[^"]*" aria-label="Pages">.*?</nav>}m]

  before do
    sign_in_as admin
    Redirect.insert_all!((1..60).map { |n| {source_path: format("/old-%02d", n), destination_url: "/new", status_code: 301, active: true, created_at: Time.current, updated_at: n.minutes.ago} })
    Redirect.find_each(&:reindex) # insert_all runs no callbacks, as a bulk import doesn't
  end

  it "shows a page of rows with Previous, the page numbers and Next" do
    get tools_redirects_path

    expect(nav).to include("1–25", "of 60", "Previous", 'rel="next"', 'aria-label="Page 3"')
    expect(response.body).to include("/old-25")
    expect(response.body).not_to include("/old-26") # newest first

    get tools_redirects_path(page: 3)

    expect(nav).to include("51–60", 'rel="prev"')
    expect(nav).not_to include('rel="next"')
    expect(response.body).to include("/old-60")
  end

  it "keeps the search on every page's link, and leaves page 1 without a number" do
    get tools_redirects_path(s: "old", page: 2)

    expect(nav).to include(%(href="#{ERB::Util.h(tools_redirects_path(s: "old", page: 3))}"))
    expect(nav).to include(%(href="#{ERB::Util.h(tools_redirects_path(s: "old"))}"))
  end

  it "has none when the list fits on one page" do
    Redirect.where("source_path > ?", "/old-10").delete_all

    get tools_redirects_path

    expect(nav).to be_nil
  end
end

RSpec.describe PaginationHelper, type: :helper do
  # Plugins written when tables loaded more rows as they scrolled still call it.
  it "draws the numbered pagination where a plugin's table had its load-more row" do
    allow(helper).to receive(:pagination_path) { |number| "/things?page=#{number}" }

    row = helper.table_next_page_row(:things_rows, Pagination.new((1..30).to_a, page: 1), columns: 4)

    expect(row).to include('colspan="4"', 'aria-current="page"', "/things?page=2")
    expect(helper.table_next_page_row(:things_rows, Pagination.new([1], page: 1), columns: 4)).to be_nil
  end
end
