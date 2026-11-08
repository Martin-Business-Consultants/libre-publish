# frozen_string_literal: true

# Append-only snapshot of a setting people edit (VERSIONED: General,
# Branding, Search, Media, Forms, Email delivery), written on every save that
# changes it, for Settings › History. Never a secret: a key that looks like
# one (Redactable::SECRET_KEY) isn't kept, and restoring leaves the current
# value of such a key in place. Encrypted secrets aren't in `data` at all.
class SettingVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[data].freeze
  VERSIONED = {"general" => "General", "branding" => "Branding", "search" => "Search", "media" => "Media",
               "forms_settings" => "Forms", "mail_delivery" => "Email delivery"}.freeze

  snapshot_of :setting

  def self.versioned?(key) = VERSIONED.key?(key.to_s)

  def self.without_secrets(data) = data.to_h.reject { |key, _| Redactable::SECRET_KEY.match?(key.to_s) }

  def label = VERSIONED.fetch(key, key.humanize)

  # Puts the setting back as this version kept it (secrets as they are now),
  # and records it.
  def restore
    Setting.changing(key) { it.data = snapshot["data"] }
    Event.record("settings.restored", key: key, version_id: id)
  end

  # As the setting would take it back: what was kept, with the secrets it
  # holds now.
  def snapshot
    current = setting.data.to_h
    {"data" => data.to_h.merge(current.select { |key, _| Redactable::SECRET_KEY.match?(key.to_s) })}
  end
end
