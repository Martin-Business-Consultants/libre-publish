# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessScheduledPublishingJob do
  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "draft",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  def make_collection
    Collection.create!(slug: "blog-#{SecureRandom.hex(3)}", name: "Blog", schema: {"fields" => []})
  end

  def make_entry(coll, attrs = {})
    CollectionEntry.create!({
      collection:    coll,
      slug:          "e-#{SecureRandom.hex(3)}",
      title:         "E",
      status:        "draft",
      locale:        "en",
      frontmatter:   {},
      body_markdown: "",
      seo:           {}
    }.merge(attrs))
  end

  describe "publishing" do
    it "flips draft pages whose publish_at has passed to published" do
      now = Time.current
      page = make_page(status: "draft", publish_at: 1.minute.ago)

      described_class.new.perform(now: now)

      page.reload
      expect(page.status).to eq("published")
      expect(page.publish_at).to be_nil
      expect(page.published_at).to be_within(2.seconds).of(now)
    end

    it "does not touch pages whose publish_at is in the future" do
      page = make_page(status: "draft", publish_at: 1.hour.from_now)
      described_class.new.perform(now: Time.current)
      expect(page.reload.status).to eq("draft")
    end

    it "is a no-op for pages already published" do
      page = make_page(status: "published", publish_at: 1.minute.ago, published_at: 2.days.ago)
      original_published_at = page.published_at

      described_class.new.perform(now: Time.current)

      page.reload
      expect(page.status).to eq("published")
      # publish_at not cleared (the scope skips already-published rows)
      expect(page.publish_at).to be_present
      expect(page.published_at).to be_within(1.second).of(original_published_at)
    end

    it "publishes collection entries the same way" do
      coll  = make_collection
      entry = make_entry(coll, status: "draft", publish_at: 1.minute.ago)

      described_class.new.perform(now: Time.current)

      expect(entry.reload.status).to eq("published")
    end
  end

  describe "unpublishing" do
    it "archives published pages whose unpublish_at has passed" do
      page = make_page(status: "published", unpublish_at: 1.minute.ago)

      described_class.new.perform(now: Time.current)

      page.reload
      expect(page.status).to eq("archived")
      expect(page.unpublish_at).to be_nil
    end

    it "leaves drafts alone" do
      page = make_page(status: "draft", unpublish_at: 1.minute.ago)
      described_class.new.perform(now: Time.current)
      expect(page.reload.status).to eq("draft")
    end
  end

  describe "when a record can't be flipped" do
    it "records why, clears its schedule and publishes the rest" do
      broken = make_page(publish_at: 1.minute.ago)
      broken.update_columns(title: "")
      fine = make_page(publish_at: 1.minute.ago)

      described_class.new.perform(now: Time.current)

      expect(fine.reload.status).to eq("published")
      expect(broken.reload).to have_attributes(status: "draft", publish_at: nil)
      row = AuditLog.find_by!(action: "page.schedule_failed")
      expect(row.target).to eq(broken)
      expect(row.metadata).to include("path" => broken.path, "scheduled" => "publish")
      expect(row.metadata["errors"].join).to match(/Title/)
    end

    it "records an entry's failure under its collection and slug" do
      coll = make_collection
      entry = make_entry(coll, status: "published", unpublish_at: 1.minute.ago)
      entry.update_columns(title: "")

      described_class.new.perform(now: Time.current)

      expect(entry.reload).to have_attributes(status: "published", unpublish_at: nil)
      expect(AuditLog.find_by!(action: "entry.schedule_failed").metadata)
        .to include("collection" => coll.slug, "slug" => entry.slug, "scheduled" => "unpublish")
    end

    it "leaves a record that hit a passing error due, carries on, and fails the run naming it" do
      busy = make_page(publish_at: 1.minute.ago)
      fine = make_page(publish_at: 1.minute.ago)
      allow_any_instance_of(Page).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        raise ActiveRecord::StatementTimeout, "database is locked" if original.receiver.id == busy.id

        original.call(*args, &block)
      end

      expect { described_class.new.perform(now: Time.current) }
        .to raise_error(described_class::Incomplete, /database is locked/)

      expect(fine.reload.status).to eq("published")
      expect(busy.reload).to have_attributes(status: "draft", publish_at: be_present)
    end

    it "still runs the entries when the pages fail" do
      entry = make_entry(make_collection, publish_at: 1.minute.ago)
      allow(Page).to receive(:publish_due).and_raise(ActiveRecord::StatementTimeout, "database is locked")

      expect { described_class.new.perform(now: Time.current) }.to raise_error(described_class::Incomplete)

      expect(entry.reload.status).to eq("published")
    end
  end

  describe "two runs at once" do
    it "flips a record once and announces it once" do
      page = make_page(publish_at: 1.minute.ago)
      stale = Page.find(page.id)
      announced = 0
      subscription = ActiveSupport::Notifications.subscribe("page.published.cms") { announced += 1 }

      expect(page.publish_on_schedule).to be(true)
      expect(stale.publish_on_schedule).to be(false)

      expect(announced).to eq(1)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  describe "validations" do
    it "rejects unpublish_at before publish_at" do
      page = Page.new(
        slug:        "x",
        title:       "T",
        status:      "draft",
        locale:      "en",
        blocks:      [],
        schema:      {"fields" => []},
        frontmatter: {},
        seo:         {},
        publish_at:  1.day.from_now,
        unpublish_at: 1.hour.from_now
      )
      expect(page).not_to be_valid
      expect(page.errors[:unpublish_at].join).to match(/after/)
    end
  end
end
