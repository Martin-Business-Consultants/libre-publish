# frozen_string_literal: true

require "openssl"
require "base64"

# Opens what the Go core sealed with its key (its internal/secret): token
# plaintexts, webhook signing secrets, settings' passwords. A sealed value is
# "go1:" and the unpadded base64 of a 12-byte nonce followed by the AES-256-GCM
# ciphertext and its 16-byte tag.
#
# The key is what the old install's DATA_DIR/secret.key holds (64 hex
# characters), or the SECRET_KEY it ran with: a passphrase, stretched with
# scrypt, and before that its SHA-256 (values sealed then still open). Any
# text given is tried every way it could be meant, as the Go core does.
#
#   keyring = GoImport::Keyring.new(File.read("old/secret.key"))
#   keyring.open("go1:…")   # => "lps_…", or nil for a value no key here opens
class GoImport::Keyring
  PREFIX = "go1:"
  SALT = "librepublish SECRET_KEY v2"
  NONCE_BYTES = 12
  TAG_BYTES = 16

  def self.sealed?(value) = value.is_a?(String) && value.start_with?(PREFIX)

  # The keys text could stand for, strongest first.
  def self.candidates(text)
    text = text.to_s.strip
    return [] if text.empty?

    keys = []
    keys << [text].pack("H*") if text.match?(/\A\h{64}\z/)
    keys << OpenSSL::KDF.scrypt(text, salt: SALT, N: 2**15, r: 8, p: 1, length: 32)
    keys << OpenSSL::Digest::SHA256.digest(text)
  end

  def initialize(*texts)
    @keys = texts.flat_map { self.class.candidates(it) }.uniq
  end

  def empty? = @keys.empty?

  # The plaintext, or nil when no key here sealed it (GCM authenticates, so a
  # wrong key fails rather than opening as noise).
  def open(value)
    return nil unless self.class.sealed?(value)

    raw = decode(value.delete_prefix(PREFIX))
    return nil if raw.nil? || raw.bytesize < NONCE_BYTES + TAG_BYTES

    @keys.each do |key|
      plain = decrypt(key, raw)
      return plain if plain
    end
    nil
  end

  private

  def decode(text)
    Base64.strict_decode64(text + "=" * (-text.length % 4))
  rescue ArgumentError
    nil
  end

  def decrypt(key, raw)
    cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
    cipher.key = key
    cipher.iv = raw.byteslice(0, NONCE_BYTES)
    cipher.auth_tag = raw.byteslice(-TAG_BYTES, TAG_BYTES)
    cipher.auth_data = ""
    (cipher.update(raw.byteslice(NONCE_BYTES...-TAG_BYTES)) + cipher.final).force_encoding(Encoding::UTF_8)
  rescue OpenSSL::Cipher::CipherError
    nil
  end
end
