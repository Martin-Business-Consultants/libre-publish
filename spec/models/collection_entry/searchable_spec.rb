# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEntry::Searchable do
  def found(term) = CollectionEntry.search_index_ids(term)

  it "indexes its body and fields, and drops out when destroyed" do
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => [{"name" => "summary", "type" => "string"}]})
    entry = collection.entries.create!(slug: "a", title: "Alpha", status: "draft", body_markdown: "Body text", frontmatter: {"summary" => "Short"})

    expect(entry.search_text).to include("Body text", "Short")
    expect(found("Alpha")).to eq([entry.id])
    expect(found("Body text")).to eq([entry.id])
    expect(found("Short")).to eq([entry.id])

    entry.destroy_permanently!
    expect(found("Alpha")).to be_empty
  end
end
