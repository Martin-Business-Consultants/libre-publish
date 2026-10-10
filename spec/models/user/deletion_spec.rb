# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  it "can be deleted after editing content: their versions stay, without an author" do
    author = create(:user)
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")
    version = page.versions.create!(blocks: [], author_id: author.id, created_at: Time.current)
    collection = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    entry_version = collection.entries.create!(slug: "a", title: "A", status: "draft").versions
      .create!(frontmatter: {}, body_markdown: "", blocks: [], author_id: author.id, created_at: Time.current)
    DeviceAuthorization.create!(user: author, user_code: "ABCD-EFGH", expires_at: 10.minutes.from_now)

    author.destroy!

    expect(version.reload.author_id).to be_nil
    expect(entry_version.reload.author_id).to be_nil
    expect(DeviceAuthorization.where(user_id: author.id)).to be_empty
  end
end
