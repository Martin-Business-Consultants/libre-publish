# frozen_string_literal: true

# Settings › GitHub was folded into Settings › Deploy, where the site's
# repository and token sit with the GitHub method that uses them; its old
# address lands there.
class Settings::GithubsController < Settings::BaseController
  requires_capability "settings:read", only: :show

  def show
    redirect_to settings_deploy_path(anchor: "github")
  end
end
