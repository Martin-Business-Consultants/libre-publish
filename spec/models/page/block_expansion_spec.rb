# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::BlockExpansion do
  let(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  def list(data, live = false) = described_class.new([{"type" => "collection_list", "data" => data}], live: live).blocks.first["resolved"]

  it "fills a collection list with its published entries, sorted and limited" do
    posts.entries.create!(slug: "old", title: "Old", status: "published", published_at: 2.days.ago, locale: "en")
    posts.entries.create!(slug: "new", title: "New", status: "published", published_at: 1.day.ago, locale: "en")
    posts.entries.create!(slug: "draft", title: "Draft", status: "draft", locale: "en")

    resolved = list("collection_slug" => "posts", "sort_by" => "published_at", "sort_dir" => "desc", "limit" => 1)

    expect(resolved["entries"].map { it["slug"] }).to eq(%w[new])
    expect(resolved["total"]).to eq(2)
    expect(resolved["collection"]).to eq("slug" => "posts", "name" => "Posts")
    expect(resolved["entries"].first).to include("collection" => "posts", "url" => "/posts/new")
  end

  it "lists drafts only where it may: never for the delivery API, whatever the block says" do
    posts.entries.create!(slug: "live", title: "Live", status: "published", published_at: 1.day.ago, locale: "en")
    posts.entries.create!(slug: "draft", title: "Draft", status: "draft", locale: "en")

    expect(list({"collection_slug" => "posts", "filter_status" => "any"}).fetch("entries").map { it["slug"] }).to contain_exactly("live", "draft")
    expect(list({"collection_slug" => "posts", "filter_status" => "any"}, true).fetch("entries").map { it["slug"] }).to eq(%w[live])
  end

  it "names the cache tags of what the blocks pull in" do
    blocks = [{"type" => "collection_list", "data" => {"collection_slug" => "posts"}}, {"type" => "contact_info"}, {"type" => "hero"}, "junk"]

    expect(described_class.cache_tags(blocks)).to eq(%w[collection:posts site])
  end

  it "says so when the collection doesn't exist" do
    expect(list("collection_slug" => "nope")).to eq("error" => "collection not found", "slug" => "nope", "entries" => [], "total" => 0)
  end

  it "fills contact details and leaves other blocks alone" do
    Setting.set("general", {"email" => "hi@example.com", "title" => "Acme", "email_from_address" => "robot@example.com"})
    blocks = described_class.new([{"type" => "contact_info"}, {"type" => "hero", "data" => {}}, "junk"]).blocks

    # The business's details, not the rest of Settings › General.
    expect(blocks[0]["resolved"]).to eq("contact" => {"email" => "hi@example.com", "title" => "Acme"})
    expect(blocks[1..]).to eq([{"type" => "hero", "data" => {}}, "junk"])
  end
end
