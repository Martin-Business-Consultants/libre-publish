# frozen_string_literal: true

require "rails_helper"

# config/initializers/active_record_encryption.rb: a site moved from another
# install keeps that install's encrypted values readable with
# CMS_PREVIOUS_SECRET_KEY_BASE.
RSpec.describe ActiveRecordEncryptionKeys do
  let(:old_secret) { "the old deployment's secret_key_base" }
  let(:encryptor) { ActiveRecord::Encryption::Encryptor.new }

  # Encrypts as the other install did: its primary key and its salt, both
  # derived from its secret_key_base, through Rails' own provider.
  def encrypted_by_old_install(text)
    config = ActiveRecord::Encryption.config
    salt = config.key_derivation_salt
    config.key_derivation_salt = described_class.derive(:key_derivation_salt, old_secret)
    provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new(described_class.derive(:primary_key, old_secret),
      key_generator: ActiveRecord::Encryption::KeyGenerator.new)
    encryptor.encrypt(text, key_provider: provider)
  ensure
    config.key_derivation_salt = salt
  end

  it "reads what the other install wrote, which this install's own keys can't" do
    ciphertext = encrypted_by_old_install("lp_old")

    expect(encryptor.decrypt(ciphertext, key_provider: described_class.previous_key_provider(old_secret))).to eq("lp_old")
    expect { encryptor.decrypt(ciphertext) }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)
    expect { encryptor.decrypt(ciphertext, key_provider: described_class.previous_key_provider("another secret")) }
      .to raise_error(ActiveRecord::Encryption::Errors::Decryption)
  end
end

RSpec.describe EncryptedValues do
  it "rewrites what it can read with this install's keys, and counts what it can't" do
    readable = ApiToken.for(create(:user))
    unreadable = ApiToken.for(create(:user))
    foreign = ActiveRecord::Encryption::Encryptor.new.encrypt("lp_x", key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("nobody's"))
    ActiveRecord::Base.connection.execute(ApiToken.sanitize_sql(["UPDATE api_tokens SET token = ? WHERE id = ?", foreign, unreadable.id]))

    tally = described_class.reencrypt

    expect(tally[:unreadable]).to eq(1)
    expect(tally[:rewritten]).to be >= 1
    expect(readable.reload.visible?).to be(true)
  end
end
