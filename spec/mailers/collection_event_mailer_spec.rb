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

  # The logo and the entry link are the CMS's (APP_HOST, example.com in
  # tests), never the public website's: the site doesn't serve CMS files or
  # the editor, so links built on it came out broken.
  it "links the logo and the entry on the CMS itself, not the public site" do
    Setting.set("general", {"site_base_url" => "https://www.acme.test"})
    Setting.set("branding", {"logo_id" => "7"})
    logo = Struct.new(:url).new("https://localhost/rails/active_storage/blobs/redirect/abc--123/logo.png")
    allow(MediaLibrary).to receive(:find).with("7").and_return(logo)

    html = sent.body.to_s

    expect(html).to include(%(src="http://example.com/rails/active_storage/blobs/redirect/abc--123/logo.png"))
    expect(html).to include(%(href="http://example.com/collections/posts/entries/hello/edit"))
    expect(html).not_to include("acme.test/rails", "acme.test/collections", "localhost")
  end

  it "leaves the logo out when Branding has none" do
    expect(sent.body.to_s).not_to include("<img")
  end
end
