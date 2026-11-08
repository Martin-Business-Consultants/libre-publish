# frozen_string_literal: true

# Settings › General: the site's identity and contact details, the admin's
# time zone and language, and how the site is served (Serving). Stored in the
# `general` setting, which the public site reads too (Setting.get("general")).
module GeneralSettings
  KEY = "general"
  # How the site is served (Serving), taken after the rest.
  SERVING_FIELDS = %w[serving api_pages api_collections].freeze

  module_function

  # What the form shows, with each field's default.
  def current
    data = Setting.get(KEY)

    {
      "title"           => data["title"].to_s,
      "description"     => data["description"].to_s,
      "default_locale"  => data["default_locale"].presence || "en",
      "timezone"        => data["timezone"].to_s,
      "admin_locale"    => AdminLocale.workspace,
      "site_base_url"   => data["site_base_url"].to_s,
      "public_origins"  => Array(data["public_origins"]),
      "phone"           => data["phone"].to_s,
      "email"           => data["email"].to_s,
      "address_line1"   => data["address_line1"].to_s,
      "city"            => data["city"].to_s,
      "state"           => data["state"].to_s,
      "zip"             => data["zip"].to_s,
      "serving"         => Serving.mode,
      "api_pages"       => data["api_pages"] == true
    }
  end

  # From the form: an unknown time zone is left as it was, the origins
  # textarea becomes a list, and the collections ticked for the API are
  # served (Serving.serve_collections). Records settings.general_updated
  # naming the fields that changed.
  def update(attrs)
    attrs = attrs.to_h.stringify_keys
    incoming = attrs.except(*SERVING_FIELDS).merge(attrs.slice(*SERVING_FIELDS))
    incoming.delete("timezone") if incoming["timezone"].present? && Time.find_zone(incoming["timezone"]).nil?
    incoming["admin_locale"] = incoming["admin_locale"].presence_in(AdminLocale::LANGUAGES.keys) || AdminLocale::DEFAULT if incoming.key?("admin_locale")

    # Newline/comma-separated origin list edited as a single textarea; the
    # canonical storage form is a normalized array.
    if (raw = incoming.delete("public_origins_raw"))
      incoming["public_origins"] = raw.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
    end

    if incoming.key?("serving")
      incoming["serving"] = incoming["serving"].presence_in(Serving::MODES.keys)
      incoming.delete("serving") if incoming["serving"].nil?
    end
    incoming["api_pages"] = ActiveModel::Type::Boolean.new.cast(incoming["api_pages"]) == true if incoming.key?("api_pages")
    Serving.serve_collections(Array(incoming.delete("api_collections")).compact_blank) if incoming.key?("api_collections")

    before = Setting.get(KEY)
    Setting.set(KEY, incoming)
    changed = incoming.keys.reject { |key| before[key].presence == incoming[key].presence }
    Event.record("settings.general_updated", fields: changed) if changed.any?
  end
end
