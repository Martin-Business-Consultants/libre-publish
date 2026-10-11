# frozen_string_literal: true

# The admin on a host of its own (CMS_ADMIN_HOST, say cms.example.com), the
# website on its own (the site URL): set, the admin, its sign-in and its
# cookie live only on the admin host, so nothing the website runs (a pasted
# script, a theme's) shares an origin with a signed-in admin. Unset, both
# share one host, as before.
#
# On the admin host, a website address goes to the website; on any other
# host, an admin address (/cms…) goes to the admin host. The API, files
# (/rails), /up and the agent and frontend bootstraps answer on both.
class AdminHost
  SHARED = %w[/api /rails /up /agent /frontend /assets /recede_historical_location /refresh_historical_location /resume_historical_location].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    admin_host = Site.admin_host or return @app.call(env)

    request = Rack::Request.new(env)
    path = request.path_info
    admin_path = path == admin_prefix || path.start_with?("#{admin_prefix}/")
    on_admin_host = [request.host, request.host_with_port].include?(admin_host)

    if on_admin_host
      return @app.call(env) if admin_path || shared?(path)

      website = Site.public_base_url
      return not_found if website.nil? || URI.parse(website).host == request.host

      redirect("#{website}#{request.fullpath}")
    elsif admin_path
      redirect("#{request.scheme}://#{admin_host}#{request.fullpath}")
    else
      @app.call(env)
    end
  end

  private

  def admin_prefix = "/#{Cms::PATH}"

  def shared?(path) = SHARED.any? { path == it || path.start_with?("#{it}/") || path.start_with?("#{it}.") }

  def redirect(location) = [302, {"location" => location, "content-type" => "text/plain"}, ["Moved to #{location}"]]

  def not_found = [404, {"content-type" => "text/plain"}, ["Not found"]]
end
