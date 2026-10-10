# frozen_string_literal: true

# Site-wide admin configuration. Distinct from `Global`, which is for
# editorially-authored singleton content surfaced to the public site (nav,
# footer, business identity). Settings are configuration the public site
# never sees: integration tokens, feature flags, default locale, etc.
#
# Stored as a thin key/value model: `Setting.get("github")` returns a hash;
# `Setting.set("github", token: "ghp_…")` merges into the value.
class Setting < ApplicationRecord
  include Eventable
  include Redactable

  # Provider API keys and the like. They used to sit in the plain `data` JSON
  # column, where a database file, a backup, or a stray `SELECT *` in a
  # console handed someone a working credential. They live here instead,
  # encrypted at rest, and are never round-tripped to a form — a settings page
  # shows "already set, ends in ab12" and nothing more.
  #
  # A JSON blob rather than a column per secret because the set of them is
  # open: every integration this CMS grows brings one, and none of them is
  # ever queried BY value, so there is nothing a column would buy.
  encrypts :secrets
  include ForgetsUnreadable

  validates :key, presence: true, uniqueness: true

  # What a site shows from Settings › General (/api/v1/site, contact_info
  # blocks, the sitemap's addresses): changing one rebuilds or purges it like
  # a publish does, or it would keep the old name, phone or address.
  SITE_FACING_GENERAL = %w[title description site_base_url default_locale phone email address_line1 city state zip].freeze

  after_update_commit :redeploy_site, if: -> { key == "general" }
  after_create_commit :redeploy_site, if: -> { key == "general" }

  scope :ordered, -> { order(:key) }

  def self.get(key)
    find_by(key: key.to_s)&.data || {}
  end

  # Merges `attrs` into the setting's data. Given a block instead, merges what
  # the block returns for the data as it is now — for a value worked out from
  # the current one (appending to a list), so two writers at once don't each
  # overwrite the other's change:
  #
  #   Setting.set("deploy") { |data| {"pending_changes" => Array(data["pending_changes"]) + [change]} }
  def self.set(key, attrs = nil)
    changing(key) do |record|
      data = record.data || {}
      record.data = data.merge((block_given? ? yield(data) : attrs).to_h.deep_stringify_keys)
    end
  end

  # Drops names from a setting's data (a value that has moved to `secrets`).
  def self.unset(key, *names)
    return unless exists?(key: key.to_s)

    changing(key) { |record| record.data = (record.data || {}).except(*names.map(&:to_s)) }
  end

  # Reads the row and writes it back in one transaction, the row re-read
  # under its lock (on SQLite the transaction is IMMEDIATE: it holds the
  # write lock from the start), so a read-modify-write can't lose another
  # one's change made in between.
  def self.changing(key)
    transaction do
      record = find_or_initialize_by(key: key.to_s)
      record.lock! if record.persisted?
      yield record
      record.save!
      record
    end
  end

  def self.delete_key(key)
    where(key: key.to_s).delete_all
  end

  # --- secrets -------------------------------------------------------------

  # nil for a key that isn't set, and for a settings row that doesn't exist —
  # "no credential" is one answer, and callers should not have to tell the two
  # apart before deciding they have nothing to authenticate with.
  def self.secret(key, name)
    find_by(key: key.to_s)&.secrets_hash&.[](name.to_s).presence
  end

  # Merges, like `set` does. A blank value is a DELETE rather than an empty
  # string: forms send "" for an untouched password field, and a stored ""
  # would read as "configured" everywhere that checks `.present?`.
  def self.set_secret(key, attrs)
    changing(key) do |record|
      record.forget_unreadable(:secrets) if record.persisted?
      merged = record.secrets_hash.merge(attrs.deep_stringify_keys)
      merged = merged.reject { |_, value| value.to_s.strip.empty? }
      record.secrets = merged.empty? ? nil : JSON.generate(merged)
    end
  end

  def secrets_hash
    parsed = JSON.parse(secrets.presence || "{}")
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, ActiveRecord::Encryption::Errors::Decryption
    # Unreadable ciphertext means the key that wrote it is gone (a site moved
    # from another install without its keys). Treat it as
    # "nothing stored" so the app boots and the settings page says "not set",
    # rather than 500ing on every request that reads a credential.
    {}
  end

  private

  def redeploy_site
    before, after = saved_change_to_data || previous_changes["data"] || [nil, nil]
    before ||= {}
    after ||= {}
    return if SITE_FACING_GENERAL.all? { before[it].presence == after[it].presence }

    Deploys.schedule_later(reason: "settings.general_updated", subject: self)
  end
end
