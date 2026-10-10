# frozen_string_literal: true

# Editor for the site-wide `general` Setting (site title, contact, the sender
# of the CMS's own notification emails, the admin's time zone).
# Persisted via Setting.set so it doesn't show up in the editorial Globals
# listing. The public site reads the same key via Setting.get("general").
class Settings::GeneralsController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  IDENTITY_FIELDS = %w[title description default_locale site_base_url public_origins_raw].freeze
  CONTACT_FIELDS  = %w[phone email address_line1 city state zip].freeze
  # Who the CMS's notification emails (collection events) come from.
  EMAIL_FIELDS    = %w[email_from_name email_from_address].freeze
  # The zone the admin shows and reads times in (Site.time_zone).
  TIME_FIELDS     = %w[timezone].freeze

  def show
    @settings = current_settings
  end

  def update
    incoming = scalar_params.to_h
    incoming.delete("timezone") if incoming.key?("timezone") && incoming["timezone"].present? && Time.find_zone(incoming["timezone"]).nil?

    # Newline/comma-separated origin list edited as a single textarea; the
    # canonical storage form is a normalized array.
    if (raw = incoming.delete("public_origins_raw"))
      incoming["public_origins"] = raw.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
    end

    before = Setting.get("general")
    Setting.set("general", incoming)
    changed = incoming.keys.reject { |key| before[key].presence == incoming[key].presence }
    Event.record("settings.general_updated", fields: changed) if changed.any?
    redirect_to settings_general_path, notice: "General settings saved"
  end

  private

  def scalar_params
    params.require(:settings).permit(*(IDENTITY_FIELDS + CONTACT_FIELDS + EMAIL_FIELDS + TIME_FIELDS))
  end

  def current_settings
    data = Setting.get("general")

    {
      "title"           => data["title"].to_s,
      "description"     => data["description"].to_s,
      "default_locale"  => data["default_locale"].presence || "en",
      "timezone"        => data["timezone"].to_s,
      "site_base_url"   => data["site_base_url"].to_s,
      "public_origins"  => Array(data["public_origins"]),
      "phone"           => data["phone"].to_s,
      "email"           => data["email"].to_s,
      "address_line1"   => data["address_line1"].to_s,
      "city"            => data["city"].to_s,
      "state"           => data["state"].to_s,
      "zip"             => data["zip"].to_s,
      "email_from_name"    => data["email_from_name"].to_s,
      "email_from_address" => data["email_from_address"].to_s
    }
  end
end
