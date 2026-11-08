# frozen_string_literal: true

# Settings → Deploy: which provider rebuilds the site (Deploys — a build-hook
# URL, or a GitHub repository_dispatch on the site's repo, set here with its
# token), and
# pausing it. Deploys fires it whenever content changes, debounced,
# and keeps a rolling log of the last 20 attempts.
class Settings::DeploysController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  def show
    @settings = Deploys.config
    @provider = Deploys.current(@settings)
  end

  def update
    Deploys::Github.configure(repo: params.dig(:settings, :github_repo), token: params.dig(:settings, :github_token))
    Deploys.configure(settings_params)
    redirect_to settings_deploy_path, notice: "Deploy settings saved"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_deploy_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def settings_params
    params.require(:settings).permit(:provider, :url, :paused)
  end
end
