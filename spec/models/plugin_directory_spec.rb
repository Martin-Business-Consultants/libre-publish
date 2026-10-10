# frozen_string_literal: true

require "rails_helper"

# A directory signed with a key made here, served from a stand-in.
RSpec.describe PluginDirectory do
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:list) do
    {plugins: [
      {key: "wordpress_import", kind: "plugin", name: "WordPress Import", description: "From an export file.",
       repo: "acme/cms-wordpress-import", author: "Acme", version: "0.1.0", commit: "a" * 40, requires: ">= 1.12"},
      {key: "healing", kind: "theme", name: "Healing Earth Design", description: "A theme.",
       repo: "acme/healing-theme", version: "0.3.1", commit: "b" * 40, requires: ">= 99"}
    ]}.to_json
  end

  around { |example| with_env("CMS_PLUGIN_DIRECTORY_KEY" => key.public_to_pem) { example.run } }

  def serve(body, signature)
    allow(described_class).to receive(:get).with(described_class.url).and_return(body)
    allow(described_class).to receive(:get).with("#{described_class.url}.sig").and_return(signature)
  end

  it "keeps a list signed with the directory's key, and reads its plugins and themes" do
    serve(list, [key.sign(nil, list)].pack("m0"))

    described_class.refresh!

    expect(described_class.plugins.map(&:key)).to eq(["wordpress_import"])
    expect(described_class.themes.first).to have_attributes(version: "0.3.1", theme?: true, compatible?: false)
    expect(described_class.find_by_repo("ACME/cms-wordpress-import").commit).to eq("a" * 40)
    expect(described_class.checked_at).to be_within(5.seconds).of(Time.current)
  end

  it "refuses a list that was changed after it was signed, or signed with another key" do
    signature = [key.sign(nil, list)].pack("m0")
    serve(list.sub("0.1.0", "0.1.1"), signature)
    expect { described_class.refresh! }.to raise_error(described_class::Invalid, /signature doesn't match/)

    other = OpenSSL::PKey.generate_key("ED25519")
    serve(list, [other.sign(nil, list)].pack("m0"))
    expect { described_class.refresh! }.to raise_error(described_class::Invalid, /signature doesn't match/)
    expect(described_class.entries).to be_empty
  end

  it "ships the public key of the directory's own signing key" do
    with_env("CMS_PLUGIN_DIRECTORY_KEY" => nil) do
      expect(described_class.public_key.oid).to eq("ED25519")
    end
  end
end
