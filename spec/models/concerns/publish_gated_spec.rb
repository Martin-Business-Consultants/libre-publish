# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublishGated do
  let(:live) { Page.create!(slug: "live", title: "Live", status: "published", locale: "en") }
  let(:draft) { Page.create!(slug: "draft", title: "Draft", status: "draft", locale: "en") }

  it "needs publish to change a live record, whatever the change" do
    live.title = "Edited"
    expect(live.publishing_write?).to be(true)
  end

  it "needs publish to unpublish a live record" do
    live.status = "draft"
    expect(live.publishing_write?).to be(true)
  end

  it "doesn't need publish to edit a draft" do
    draft.title = "Edited"
    expect(draft.publishing_write?).to be(false)
  end

  it "needs publish to publish or schedule a draft" do
    draft.status = "published"
    expect(draft.publishing_write?).to be(true)

    draft.reload.publish_at = 1.day.from_now
    expect(draft.publishing_write?).to be(true)
  end

  it "treats a global as always live once it exists" do
    global = Global.create!(slug: "nav", name: "Nav", schema: {"fields" => []}, data: {})
    expect(Global.new(slug: "footer", name: "Footer").publishing_write?).to be(false)
    expect(global.publishing_write?).to be(true)
  end
end
