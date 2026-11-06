# frozen_string_literal: true

require "rails_helper"

# Values sealed by the Go core itself (librepublishgo v2.10, its
# internal/secret): the webhook secret in spec/fixtures/go_backups/site.tar.gz
# under the secret.key beside it (script/go_backup_fixture), and a service
# token sealed under SECRET_KEY="open sesame" (`SECRET_KEY="open sesame"
# librepublish token create`).
RSpec.describe GoImport::Keyring do
  let(:fixtures) { Rails.root.join("spec/fixtures/go_backups") }
  let(:key_file) { fixtures.join("secret.key").read }
  let(:webhook_secret) do
    Dir.mktmpdir do |dir|
      archive = GoImport::Archive.new(fixtures.join("site.tar.gz"), into: dir).unpack
      db = SQLite3::Database.new(archive.database.to_s)
      db.get_first_value("SELECT secret FROM webhooks").tap { db.close }
    end
  end
  let(:passphrase_sealed) { "go1:CmDPAH2JnO+OWJFrRs4dviSLVHVhlVLmo3Fa2T7WWmSH12LZTt0Sgl3V1vjyLjRBUps6by2zbMym+mlrGMhZUf8iZ1xop8pSlZk9" }

  it "opens what a secret.key sealed" do
    expect(described_class.new(key_file).open(webhook_secret)).to eq("whsec_go_fixture_secret_1234")
  end

  it "opens what a SECRET_KEY passphrase sealed, stretched with scrypt as the Go core stretches it" do
    expect(described_class.new("open sesame").open(passphrase_sealed)).to eq("lps_5d_qBR0JDPWmEICZ15xqR9sx0P4DVkAJ2mFM-R-IqwE")
  end

  it "opens what a passphrase sealed before it was stretched (its SHA-256)" do
    key = OpenSSL::Digest::SHA256.digest("old phrase")
    cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
    cipher.key = key
    nonce = cipher.random_iv
    sealed = "go1:" + Base64.strict_encode64(nonce + cipher.update("legacy") + cipher.final + cipher.auth_tag).delete("=")

    expect(described_class.new("old phrase").open(sealed)).to eq("legacy")
  end

  it "tries every key it was given" do
    expect(described_class.new("not it", key_file).open(webhook_secret)).to eq("whsec_go_fixture_secret_1234")
  end

  it "opens nothing with the wrong key, a damaged value, or what isn't sealed" do
    keyring = described_class.new(key_file)

    expect(described_class.new("open sesame").open(webhook_secret)).to be_nil
    expect(keyring.open(webhook_secret.sub("z+8a", "z+8b"))).to be_nil
    expect(keyring.open("go1:short")).to be_nil
    expect(keyring.open("go1:@@not base64@@")).to be_nil
    expect(keyring.open("plain text")).to be_nil
    expect(described_class.new.open(webhook_secret)).to be_nil
  end

  it "knows a sealed value, and has no keys from blank text" do
    expect(described_class.sealed?(webhook_secret)).to be(true)
    expect(described_class.sealed?("whsec_x")).to be(false)
    expect(described_class.sealed?(nil)).to be(false)
    expect(described_class.new("", nil, "  ")).to be_empty
  end
end
