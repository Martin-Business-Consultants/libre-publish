# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionSnapshot do
  def page_with_versions(slug, count)
    Page.create!(slug: slug, title: slug.titleize, status: "draft", locale: "en").tap do |page|
      page.versions.delete_all
      count.times { |i| page.versions.create!(blocks: [{"type" => "text", "data" => {"n" => i}}], created_at: i.minutes.ago) }
    end
  end

  it "keeps the newest versions of each page and deletes the rest" do
    busy = page_with_versions("busy", 5)
    quiet = page_with_versions("quiet", 2)

    expect(PageVersion.prune(keep: 3)).to eq(2)

    expect(busy.versions.reload.newest_first.map { it.blocks.first["data"]["n"] }).to eq([0, 1, 2])
    expect(quiet.versions.reload.count).to eq(2)
  end

  it "prunes entries' versions the same way" do
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    entry = collection.entries.create!(slug: "a", title: "A", status: "draft")
    entry.versions.delete_all
    4.times { |i| entry.versions.create!(frontmatter: {}, body_markdown: "v#{i}", blocks: [], created_at: i.minutes.ago) }

    expect(CollectionEntryVersion.prune(keep: 1)).to eq(3)
    expect(entry.versions.reload.pluck(:body_markdown)).to eq(["v0"])
  end

  it "keeps 100 unless the install says otherwise" do
    expect(PageVersion.keep_limit({})).to eq(100)
    expect(PageVersion.keep_limit("CMS_VERSIONS_KEEP" => "20")).to eq(20)
    expect(PageVersion.keep_limit("CMS_VERSIONS_KEEP" => "0")).to eq(100)
    expect(PageVersion.keep_limit("CMS_VERSIONS_KEEP" => "lots")).to eq(100)
  end
end
