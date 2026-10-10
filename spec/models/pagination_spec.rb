# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pagination do
  def page(number, total: 312, per: 25) = described_class.new((1..total).to_a, page: number, per: per)

  it "numbers the pages around this one, the first and the last, with gaps between" do
    expect(page(6).window).to eq([1, nil, 4, 5, 6, 7, 8, nil, 13])
    expect(page(1).window).to eq([1, 2, 3, nil, 13])
    expect(page(13).window).to eq([1, nil, 11, 12, 13])
    expect(page(4).window).to eq([1, 2, 3, 4, 5, 6, nil, 13])
    expect(page(1, total: 60).window).to eq([1, 2, 3])
  end

  it "says which rows these are, and where Previous and Next go" do
    expect(page(2)).to have_attributes(first_row: 26, last_row: 50, total_count: 312, previous_number: 1, next_number: 3, many?: true)
    expect(page(13)).to have_attributes(first_row: 301, last_row: 312, next_number: nil, last?: true)
    expect(page(1)).to have_attributes(previous_number: nil, first?: true)
    expect(page(1, total: 0)).to have_attributes(first_row: 0, last_row: 0, page_count: 1, many?: false, records: [])
  end

  it "shows the last page for one past it, and the first for anything that isn't a number" do
    expect(page(99).number).to eq(13)
    expect(page("2").records.first).to eq(26)
    expect(page(nil).number).to eq(1)
    expect(described_class.new([1], page: ActionController::Parameters.new(title: "x")).number).to eq(1)
  end

  it "pages a relation by offset and limit" do
    3.times { |n| Redirect.create!(source_path: "/old-#{n}", destination_url: "/new", status_code: 301) }

    pagination = described_class.new(Redirect.order(:source_path), page: 2, per: 2)

    expect(pagination.total_count).to eq(3)
    expect(pagination.records.map(&:source_path)).to eq(["/old-2"])
  end
end
