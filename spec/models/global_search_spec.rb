# frozen_string_literal: true

require "rails_helper"

RSpec.describe GlobalSearch do
  let(:admin) { create(:user) }

  before do
    Page.create!(slug: "pricing", title: "Pricing", status: "draft", locale: "en")
    Global.create!(slug: "footer", name: "Footer", data: {}, description: "Opening hours and pricing notes")
    Redirect.create!(source_path: "/old-pricing", destination_url: "/pricing", status_code: 301)
  end

  it "finds every kind of record that holds the term, any part of a word" do
    results = described_class.new("pric", user: admin).then { it.offset(0).limit(25) }

    expect(results.map { it.class.name }).to contain_exactly("Page", "Global", "Redirect")
    expect(results.find { it.is_a?(Global) }.hit.highlight(:body)).to include("<mark>pric</mark>ing")
    expect(described_class.new("pric", user: admin).count).to eq(3)
  end

  it "finds only what the person's role can read" do
    reader = create(:user, admin: false)
    reader.role.update!(permissions: %w[pages:read])

    results = described_class.new("pricing", user: reader).offset(0).limit(25)

    expect(results.map { it.class.name }).to eq(["Page"])
  end

  it "leaves out the trash, and searches nothing for a term too short" do
    Page.find_by!(slug: "pricing").trash

    expect(described_class.new("pricing", user: admin).offset(0).limit(25).map { it.class.name }).not_to include("Page")
    expect(described_class.new("pr", user: admin)).to have_attributes(searchable?: false, count: 0)
    expect(described_class.new("pr", user: admin).limit(25)).to eq([])
  end
end
