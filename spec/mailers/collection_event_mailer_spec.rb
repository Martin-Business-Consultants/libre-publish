# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollectionEventMailer do
  let(:collection) { Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []}) }
  let(:entry) { collection.entries.create!(slug: "hello", title: "Hello", status: "draft", locale: "en") }

  def sent
    described_class.with(collection: collection, entry: entry, event: "created", payload: {}, recipients: ["ed@acme.test"]).event
  end

  it "sends from the core's sender in Settings › General" do
    Setting.set("general", {"email_from_name" => "Acme", "email_from_address" => "news@acme.test"})
    Setting.set("forms_settings", {"from_name" => "Forms", "from_email" => "forms@acme.test"})

    expect(sent[:from].value).to eq(%("Acme" <news@acme.test>))
  end

  it "falls back to the Forms plugin's sender, as it used before, then the default" do
    Setting.set("forms_settings", {"from_name" => "Forms", "from_email" => "forms@acme.test"})
    expect(sent[:from].value).to eq(%("Forms" <forms@acme.test>))

    Setting.delete_key("forms_settings")
    expect(sent.from).to eq([described_class.default_from_email])
  end

  def html(mail) = (mail.html_part || mail).body.decoded

  # The entry link is the CMS's (APP_HOST, example.com in tests), never the
  # public website's: the site doesn't serve the editor.
  it "links the entry on the CMS itself, not the public site" do
    Setting.set("general", {"site_base_url" => "https://www.acme.test"})

    expect(html(sent)).to include(%(href="http://example.com/collections/posts/entries/hello/edit"))
    expect(html(sent)).not_to include("acme.test/collections")
  end

  # Inline, so it shows in a client that won't fetch remote images.
  it "carries the Branding logo inline, once" do
    asset = Asset.create!(folder: "/branding", name: "Logo", file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png"))
    Setting.set("branding", {"logo_id" => asset.id.to_s})

    mail = sent

    expect(mail.attachments.size).to eq(1)
    expect(mail.attachments.first).to be_inline
    expect(mail.attachments.first.content_id).to eq("<logo@cms>")
    expect(html(mail).scan(%(src="cid:logo@cms")).size).to eq(1)
  end

  it "leaves the logo out when Branding has none, or one no mail client draws" do
    expect(html(sent)).not_to include("<img")

    svg = Asset.create!(folder: "/branding", name: "Logo", file: Rack::Test::UploadedFile.new(Rails.root.join("public/icon.svg"), "image/svg+xml"))
    Setting.set("branding", {"logo_id" => svg.id.to_s})
    expect(html(sent)).not_to include("<img")
    expect(sent.attachments).to be_empty
  end
end
