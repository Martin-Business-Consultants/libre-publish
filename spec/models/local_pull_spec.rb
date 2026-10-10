# frozen_string_literal: true

require "rails_helper"

# A pull's import is TenantImport's (spec'd there); here, the refusal outside
# development and what makes a pulled copy safe to work on.
RSpec.describe LocalPull do
  let(:out) { StringIO.new }

  it "only runs in development, since it replaces the database it lands on" do
    expect { described_class.new("backup.tar.gz", out: out).call }.to raise_error(described_class::Refused, /only runs in development/)
  end

  describe "making the copy safe" do
    let(:pull) { described_class.new("backup.tar.gz", local_url: "http://localhost:3000", out: out) }

    before do
      Setting.set("general", {"site_base_url" => "https://acme.example"})
      Setting.set("deploy", {"provider" => "build_hook", "hook_url" => "https://api.example/hook"})
      Webhook.create!(name: "Search", url: "https://hooks.example/in", events: ["page.published"])
    end

    it "keeps everything inside: no webhooks, deploys or IndexNow, local addresses, and a local admin" do
      pull.send(:localize)

      expect(Setting.get("general")["site_base_url"]).to eq("http://localhost:3000")
      expect(Webhook.where(active: true)).to be_empty
      expect(Setting.find_by(key: "deploy")).to be_nil
      expect(SearchSettings.get["indexnow"]).to be(false)
      local = User.find_by!(email: described_class::LOCAL_EMAIL)
      expect(local.authenticate(described_class::LOCAL_PASSWORD)).to be_truthy
      expect(local).to be_admin
      expect(out.string).to include("local@localhost / password1234", "it was https://acme.example")
    end

    it "leaves out everyone else's account, and their tokens, without_people" do
      someone = create(:user, email: "someone@acme.example")

      described_class.new("backup.tar.gz", without_people: true, out: out).send(:localize)

      expect(User.pluck(:email)).to eq([described_class::LOCAL_EMAIL])
      expect(User.exists?(someone.id)).to be(false)
    end
  end
end
