# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trash do
  def page(slug) = Page.create!(slug: slug, title: slug.titleize, status: "draft", locale: "en")

  it "finds a trashed record by the kind a route names, and refuses kinds it doesn't know" do
    record = page("gone").tap(&:discard!)

    expect(described_class.find("page", record.id)).to eq(record)
    expect { described_class.find("nope", record.id) }.to raise_error(Trash::UnknownKind, /expected one of page/)
  end

  it "lists what's in the trash newest first, with counts" do
    older = page("older").tap(&:discard!)
    travel 1.minute
    newer = page("newer").tap(&:discard!)

    expect(described_class.contents.map(&:last)).to eq([newer, older])
    expect(described_class.contents(kind: "page", limit: 1).map(&:last)).to eq([newer])
    expect(described_class.counts["page"]).to eq(2)
  end

  it "records restoring and purging" do
    record = page("back").tap(&:discard!)

    described_class.restore("page", record)
    expect(record.reload).not_to be_discarded
    expect(AuditLog.last).to have_attributes(action: "trash.restored", metadata: {"kind" => "page"})

    record.discard!
    described_class.purge("page", record)
    expect(Page.with_discarded.exists?(record.id)).to be(false)
    expect(AuditLog.last).to have_attributes(action: "trash.purged", target_label: "Back")
  end

  it "purges only what was trashed before the cutoff" do
    old = page("old").tap(&:discard!)
    old.update_column(:deleted_at, 40.days.ago)
    fresh = page("fresh").tap(&:discard!)

    expect(described_class.purge_expired(30.days.ago)).to eq("Page" => 1)
    expect(Page.with_discarded.pluck(:id)).to eq([fresh.id])
  end

  it "keeps purging past a record that can't be deleted, and reports it" do
    stuck = page("stuck").tap(&:discard!)
    gone = page("gone").tap(&:discard!)
    allow_any_instance_of(Page).to receive(:destroy_permanently!).and_wrap_original do |original, *args|
      raise ActiveRecord::InvalidForeignKey, "held" if original.receiver.id == stuck.id

      original.call(*args)
    end
    allow(Rails.error).to receive(:report)

    expect(described_class.purge_expired(1.minute.from_now)).to eq("Page" => 1)
    expect(Page.with_discarded.pluck(:id)).to eq([stuck.id])
    expect(Page.with_discarded.exists?(gone.id)).to be(false)
    expect(Rails.error).to have_received(:report).with(an_instance_of(ActiveRecord::InvalidForeignKey), hash_including(handled: true))
  end

  it "records a purge only when the record went" do
    record = page("held").tap(&:discard!)
    allow(record).to receive(:destroy_permanently!).and_raise(ActiveRecord::InvalidForeignKey, "held")

    expect { described_class.purge("page", record) }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(AuditLog.where(action: "trash.purged")).to be_empty
  end

  it "purges a category entry other entries still use, leaving them uncategorized" do
    categories = Collection.create!(slug: "kinds", name: "Kinds", schema: {"fields" => []})
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}, categories_collection: categories)
    category = categories.entries.create!(slug: "news", title: "News", status: "published")
    post = posts.entries.create!(slug: "hello", title: "Hello", status: "published", category_entry_id: category.id)
    on_page = page("about").tap { it.update_column(:category_entry_id, category.id) }
    category.discard!

    expect(described_class.purge_expired(1.minute.from_now)).to eq("CollectionEntry" => 1)
    expect(post.reload.category_entry_id).to be_nil
    expect(on_page.reload.category_entry_id).to be_nil
  end
end
