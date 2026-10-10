# frozen_string_literal: true

# Keys for ActiveRecord encryption. The only encrypted attribute today is
# `ApiToken#token`, which has to be *decryptable* — the whole point is that
# a user can come back later and read their own token.
#
# Resolution order, per key:
#
#   1. ENV — AR_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT
#   2. derived from secret_key_base
#
# (2) is what keeps dev, test, and already-deployed instances working with
# no extra setup. The trade-off: token decryptability is tied to
# secret_key_base, so rotating that leaves stored tokens unreadable (the UI
# degrades to "rotate to reveal" — nothing is lost but the old plaintext).
# Set (1) to decouple the two.
#
# Values written by another install, under its keys (a site moved here from
# the old shared deployment, or an install whose secret_key_base changed),
# stay readable with CMS_PREVIOUS_SECRET_KEY_BASE: that install's
# secret_key_base, from which its keys are derived the same way. Rails then
# tries this install's keys and then those when it decrypts, and always
# writes with this install's. `bin/rails cms:reencrypt` rewrites everything
# with this install's keys, after which the previous one can go.
#
# This runs as a plain initializer rather than `config.active_record.encryption.*`
# because ActiveRecord's own encryption initializer has already fired by the
# time config/initializers/* load; calling `configure` directly is what that
# initializer does anyway.
module ActiveRecordEncryptionKeys
  KEYS = {
    primary_key:         "AR_ENCRYPTION_PRIMARY_KEY",
    deterministic_key:   "AR_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "AR_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  def self.resolve
    KEYS.to_h { |name, env_name| [name, fetch(name, env_name)] }
  end

  def self.fetch(name, env_name)
    ENV[env_name].presence || derive(name)
  end

  def self.derive(name, secret_key_base = Rails.application.secret_key_base)
    Rails.application.key_generator(secret_key_base).generate_key("active_record_encryption/#{name}", 32).unpack1("H*")
  end

  # The key another install encrypted with, given its secret_key_base: its
  # primary key, derived with its salt (Rails' own derivation would use this
  # install's).
  def self.previous_key_provider(secret_key_base)
    password = derive(:primary_key, secret_key_base)
    salt = derive(:key_derivation_salt, secret_key_base)
    key = ActiveSupport::KeyGenerator.new(password, hash_digest_class: ActiveRecord::Encryption.config.hash_digest_class)
      .generate_key(salt, ActiveRecord::Encryption.cipher.key_length)
    ActiveRecord::Encryption::KeyProvider.new(ActiveRecord::Encryption::Key.new(key))
  end
end

ActiveRecord::Encryption.configure(**ActiveRecordEncryptionKeys.resolve)

if (previous = ENV["CMS_PREVIOUS_SECRET_KEY_BASE"].presence)
  ActiveRecord::Encryption.config.previous = [{key_provider: ActiveRecordEncryptionKeys.previous_key_provider(previous)}]
end
