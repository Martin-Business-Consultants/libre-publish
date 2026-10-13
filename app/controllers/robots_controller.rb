# frozen_string_literal: true

# The Sitemap screen's robots.txt: what the site publishes (written here,
# or made from Settings › Search plus extra lines), with what's likely
# wrong with it, edited and previewed. Saving it rebuilds the site.
class RobotsController < ApplicationController
  requires_capability "pages:read", only: :edit
  requires_capability "settings:write", only: :update

  def edit
    @settings = SearchSettings.get
    @base_url = Setting.get("general")["site_base_url"].presence&.chomp("/") || Site.public_base_url || request.base_url
    # What's published: this host's own with a theme, a frontend's (no admin lines) without one.
    @robots = Website::Robots.new(@base_url, settings: @settings, frontend: !Website.enabled?)
    @text = @robots.to_s
    @warnings = Website::Robots.warnings(@text)
  end

  def update
    attributes = params.require(:robots).permit(:robots_mode, :robots_custom, :robots_extra)
    attributes[:robots_custom] = Website::Robots.new(base_url_for_reset, frontend: !Website.enabled?).generated if params[:reset]
    attributes[:robots_mode] = "generated" if params[:reset]
    SearchSettings.update_robots(attributes)
    Event.record("settings.robots_updated")
    Deploys.schedule_later(reason: "settings.robots_updated")
    redirect_to sitemap_robots_path, notice: params[:reset] ? "robots.txt is made from Settings › Search again" : "robots.txt saved: the site picks it up on its next build"
  end

  private

  def base_url_for_reset = Setting.get("general")["site_base_url"].presence || Site.public_base_url || request.base_url
end
