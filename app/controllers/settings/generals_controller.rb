# frozen_string_literal: true

# Editor for the site-wide `general` Setting (GeneralSettings): site title,
# contact, the admin's time zone, how the site is served.
class Settings::GeneralsController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  IDENTITY_FIELDS = %w[title description default_locale site_base_url public_origins_raw].freeze
  CONTACT_FIELDS  = %w[phone email address_line1 city state zip].freeze
  # The zone the admin shows and reads times in (Site.time_zone).
  TIME_FIELDS     = %w[timezone admin_locale].freeze

  def show
    @settings = GeneralSettings.current
    @collections = Collection.order(:name).to_a
    @tokens_reading = Serving.recently_used_tokens
  end

  def update
    GeneralSettings.update(general_params)
    redirect_to settings_general_path, notice: "General settings saved"
  end

  private

  # How the site is served (Serving) comes with the rest: the mode, whether
  # the pages (and the globals) go over the API, and which collections do.
  # The collections' list comes with a hidden blank, so unticking every one
  # still arrives.
  def general_params
    params.require(:settings).permit(*(IDENTITY_FIELDS + CONTACT_FIELDS + TIME_FIELDS), :serving, :api_pages, api_collections: [])
  end
end
