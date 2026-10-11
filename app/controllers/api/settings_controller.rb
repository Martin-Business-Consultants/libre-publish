# frozen_string_literal: true

# Settings over the API. Any field whose name looks like a secret (api_key,
# secret, token, password, client_secret) is masked on read, the same rule as
# globals (Redactable). Writes still go through `data: {}` so secrets can be
# set via the API; they just can't be read back over it.
class Api::SettingsController < Api::BaseController
  enforce_authorization
  requires_capability "settings:read",  only: [:index, :show]
  requires_capability "settings:write", only: [:create, :update, :destroy]

  before_action :refuse_managed_key!, only: [:create, :update, :destroy]
  before_action :set_setting, only: [:show, :update, :destroy]

  # Settings the CMS keeps itself, read-only here: the signed plugin
  # directory (installing from it trusts it), what the update checks found,
  # and which plugins are on and set up (Settings › Plugins).
  MANAGED_KEYS = %w[plugin_directory plugin_updates updates plugins plugin_setups].freeze

  def index
    @settings = Setting.ordered
  end

  def show
  end

  def create
    @setting = Setting.create!(params.require(:setting).permit(:key, data: {}))
    @setting.track_event(:created, key: @setting.key)
    render :show, status: :created
  end

  def update
    @setting.update!(data: (@setting.data || {}).merge(setting_data.to_h))
    @setting.track_event(:updated, key: @setting.key)
    render :show
  end

  def destroy
    @setting.track_event(:deleted, key: @setting.key)
    @setting.destroy!
    head :no_content
  end

  private

  def refuse_managed_key!
    key = (params[:key] || params.dig(:setting, :key)).to_s
    return unless MANAGED_KEYS.include?(key)

    render json: {error: "forbidden", message: "#{key} is kept by the CMS itself and can't be written over the API."}, status: :forbidden
  end

  def set_setting
    @setting = Setting.find_by!(key: params[:key])
  end

  def setting_data
    params.require(:setting).permit(data: {})[:data] || {}
  end
end
