# frozen_string_literal: true

require "rails_helper"

# What a page reports when its blocks, fields, schema, parent, category or
# tags are wrong: the messages the editor and the API show, word for word.
RSpec.describe Page, "validation messages" do
  def page(attrs = {})
    Page.new({slug: "p-#{SecureRandom.hex(3)}", title: "P", status: "draft", locale: "en",
              blocks: [], schema: {"fields" => []}, frontmatter: {}, seo: {}}.merge(attrs))
  end

  def errors_on(record, attribute)
    record.valid?
    record.errors[attribute]
  end

  before do
    BlockType.create!(slug: "hero", label: "Hero", fields: [{"name" => "heading", "type" => "string", "required" => true}])
  end

  it "names each bad block by its position" do
    blocks = [{"type" => "hero", "data" => {}}, "text", {"type" => 3}, {"type" => "nope"}]

    expect(errors_on(page(blocks: blocks), :blocks)).to eq([
      "blocks[0].data.heading is required",
      "blocks[1] must be an object",
      "blocks[2].type must be a string",
      "blocks[3]: unknown type 'nope'"
    ])
    expect(errors_on(page(blocks: {"type" => "hero"}), :blocks)).to eq(["must be an array"])
  end

  it "checks its schema's shape and its frontmatter against it" do
    expect(errors_on(page(schema: "x"), :schema)).to eq(["must be an object"])
    expect(errors_on(page(schema: {"fields" => "x"}), :schema)).to eq(["fields must be an array"])
    expect(errors_on(page(schema: {"fields" => [{"name" => "b", "type" => "blocks"}]}), :schema)).to be_present
    expect(errors_on(page(frontmatter: "x"), :frontmatter)).to eq([". must be an object"])

    fields = {"fields" => [{"name" => "summary", "type" => "string", "required" => true}]}
    expect(errors_on(page(schema: fields), :frontmatter)).to eq(["summary is required"])
  end

  it "refuses itself, or a descendant, as its parent" do
    root = Page.create!(slug: "root", title: "Root", status: "draft", locale: "en")
    child = Page.create!(slug: "child", title: "Child", status: "draft", locale: "en", parent: root)

    root.parent_id = root.id
    expect(errors_on(root, :parent_id)).to eq(["can't be the page itself"])
    root.parent_id = child.id
    expect(errors_on(root, :parent_id)).to eq(["can't be a descendant of this page"])
  end

  it "takes its category and tags from the page pools, and only from them" do
    news = Collection.create!(slug: "news", name: "News", schema: {"fields" => []}).entries.create!(slug: "n", title: "N", status: "published")

    expect(errors_on(page(category: news), :category)).to eq(["cannot be set — no 'page-categories' collection exists"])
    expect(errors_on(page(tags: [news]), :tags)).to eq(["cannot be set — no 'page-tags' collection exists"])

    categories = Collection.create!(slug: "page-categories", name: "Categories", schema: {"fields" => []})
    tags = Collection.create!(slug: "page-tags", name: "Tags", schema: {"fields" => []})
    expect(errors_on(page(category: news), :category)).to eq(["must come from the 'page-categories' collection"])
    expect(errors_on(page(tags: [news]), :tags)).to eq(["must all come from the 'page-tags' collection"])

    guide = categories.entries.create!(slug: "guide", title: "Guide", status: "published")
    seo = tags.entries.create!(slug: "seo", title: "SEO", status: "published")
    expect(page(category: guide, tags: [seo])).to be_valid
  end
end
