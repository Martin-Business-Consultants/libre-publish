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
  # The zone the admin shows and reads times in (Site.time_zone).
  TIME_FIELDS     = %w[timezone].freeze

  def show
    @settings = current_settings
    @collections = Collection.order(:name).to_a
    @tokens_reading = Serving.recently_used_tokens
  end

  def update
    incoming = scalar_params.to_h
    incoming.delete("timezone") if incoming.key?("timezone") && incoming["timezone"].present? && Time.find_zone(incoming["timezone"]).nil?

    # Newline/comma-separated origin list edited as a single textarea; the
    # canonical storage form is a normalized array.
    if (raw = incoming.delete("public_origins_raw"))
      incoming["public_origins"] = raw.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
    end

    serving = serving_params
    incoming.merge!(serving.except("api_collections"))
    serve_collections(serving["api_collections"]) if serving.key?("api_collections")

    before = Setting.get("general")
    Setting.set("general", incoming)
    changed = incoming.keys.reject { |key| before[key].presence == incoming[key].presence }
    Event.record("settings.general_updated", fields: changed) if changed.any?
    redirect_to settings_general_path, notice: "General settings saved"
  end

  private

  # How the site is served (Serving): the mode, whether the pages (and the
  # globals) go over the API, and which collections do. The collections'
  # list comes with a hidden blank, so unticking every one still arrives.
  def serving_params
    permitted = params.require(:settings).permit(:serving, :api_pages, api_collections: []).to_h
    permitted["serving"] = permitted["serving"].presence_in(Serving::MODES.keys) if permitted.key?("serving")
    permitted.delete("serving") if permitted["serving"].nil? && permitted.key?("serving")
    permitted["api_pages"] = ActiveModel::Type::Boolean.new.cast(permitted["api_pages"]) == true if permitted.key?("api_pages")
    permitted["api_collections"] = Array(permitted["api_collections"]).compact_blank if permitted.key?("api_collections")
    permitted
  end

  def serve_collections(slugs)
    Collection.find_each { it.update_column(:api_enabled, slugs.include?(it.slug)) unless it.api_enabled? == slugs.include?(it.slug) }
  end

  def scalar_params
    params.require(:settings).permit(*(IDENTITY_FIELDS + CONTACT_FIELDS + TIME_FIELDS))
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
      "serving"         => Serving.mode,
      "api_pages"       => data["api_pages"] == true
    }
  end
end
