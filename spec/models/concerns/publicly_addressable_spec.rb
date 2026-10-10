# frozen_string_literal: true

require "rails_helper"

RSpec.describe PubliclyAddressable do
  before { Setting.set("general", default_locale: "en") }

  it "serves the home page at the root, in its locale's prefix when it isn't the default" do
    expect(Page.new(slug: "home", path: "home", locale: "en").public_path).to eq("/")
    expect(Page.new(slug: "home", path: "home", locale: "fr").public_path).to eq("/fr")
  end

  it "prefixes every locale but the default, once" do
    expect(Page.new(path: "about", locale: "en").public_path).to eq("/about")
    expect(Page.new(path: "a-propos", locale: "fr").public_path).to eq("/fr/a-propos")
    expect(Page.new(path: "fr/a-propos", locale: "fr").public_path).to eq("/fr/a-propos")

    collection = Collection.new(slug: "posts")
    expect(CollectionEntry.new(collection: collection, slug: "bonjour", locale: "fr").public_path).to eq("/fr/posts/bonjour")
  end

  it "lets a canonical win" do
    expect(Page.new(path: "about", locale: "fr", seo: {"canonical_url" => "/elsewhere"}).public_path).to eq("/elsewhere")
  end
end
