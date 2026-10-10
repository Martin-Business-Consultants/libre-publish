# frozen_string_literal: true

# Settings › Search (SearchSettings): which AI crawlers may read the site,
# who the site is in its structured data, and what robots.txt adds.
class Settings::SearchesController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  def show
    @search = SearchSettings.get
    @base_url = Setting.get("general")["site_base_url"].presence&.chomp("/") || request.base_url
  end

  def update
    SearchSettings.update(params.fetch(:search, {}).permit(:ai_search, :ai_training, :organization, :same_as, :robots_extra))
    redirect_to settings_search_path, notice: "Search settings saved."
  end
end
