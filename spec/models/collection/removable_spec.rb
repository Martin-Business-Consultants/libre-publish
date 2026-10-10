# frozen_string_literal: true

require "rails_helper"

RSpec.describe Collection::Removable do
  def make(slug) = Collection.create!(slug: slug, name: slug.titleize, schema: {"fields" => []})

  it "deletes a collection and its entries, recording it first" do
    collection = make("posts")
    collection.entries.create!(slug: "a", title: "A", status: "draft")

    collection.remove

    expect(Collection.exists?(collection.id)).to be(false)
    expect(CollectionEntry.with_discarded.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "collection.deleted", metadata: {"slug" => "posts"})
  end

  it "deletes a set under one event naming the ones found" do
    Collection.remove_all([make("a"), make("b")])

    expect(Collection.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "collection.bulk_deleted", target: nil,
      metadata: {"count" => 2, "slugs" => %w[a b]})
  end

  it "records nothing for an empty set" do
    expect { Collection.remove_all([]) }.not_to change(AuditLog, :count)
  end

  it "deletes a set all or nothing" do
    kept = make("kept")
    held = make("held")
    allow(held).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, "held")

    expect { Collection.remove_all([kept, held]) }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(Collection.where(slug: %w[kept held]).count).to eq(2)
  end

  it "deletes a collection another one draws its categories and tags from" do
    pool = make("pool")
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}, categories_collection: pool, tags_collection: pool)

    pool.remove

    expect(posts.reload).to have_attributes(categories_collection_id: nil, tags_collection_id: nil)
  end
end
