# frozen_string_literal: true

require "rails_helper"

RSpec.describe Website::Address do
  let!(:home) { Page.create!(slug: "home", title: "Home", status: "published", locale: "en") }
  let!(:about) { Page.create!(slug: "about", title: "About", status: "published", locale: "en") }
  let!(:draft) { Page.create!(slug: "soon", title: "Soon", status: "draft", locale: "en") }
  let(:posts) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }

  it "finds the home page at /, and a page at its path, with or without a trailing slash" do
    expect(described_class.new("/").record).to eq(home)
    expect(described_class.new("/about").record).to eq(about)
    expect(described_class.new("/about/").record).to eq(about)
  end

  it "finds an entry at /<collection>/<slug>" do
    entry = posts.entries.create!(slug: "hello", title: "Hello", status: "published", locale: "en")

    expect(described_class.new("/posts/hello").record).to eq(entry)
    expect(described_class.new("/posts/hello/extra").record).to be_nil
    expect(described_class.new("/nope/hello").record).to be_nil
  end

  it "shows a draft only when asked for drafts (an editor's preview)" do
    expect(described_class.new("/soon").record).to be_nil
    expect(described_class.new("/soon", drafts: true).record).to eq(draft)
  end
end
