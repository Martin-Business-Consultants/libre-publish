# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :use_site_time_zone, if: :admin_page_request?
  # The admin's Content-Security-Policy, and the editor's preview's, which
  # the admin draws: scripts only from this site (its own files, and inline
  # ones it marks with the request's nonce) and Cloudflare Turnstile, so a
  # script in content — a javascript: link, HTML that got through somewhere —
  # can't run as whoever is signed in. Styles may be inline (themes and the
  # editors set them); images from anywhere https. Framed only by itself.
  # Settings › Security policy adds sources to it, a directive at a time,
  # and what it blocks is reported there (/csp-reports).
  content_security_policy do |policy|
    extra = SecurityPolicy.get["admin_sources"]
    policy.default_src :self
    policy.script_src :self, "https://challenges.cloudflare.com", *extra["script-src"]
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com", *extra["style-src"]
    policy.font_src :self, :data, "https://fonts.gstatic.com", *extra["font-src"]
    policy.img_src :self, :data, :blob, :https
    policy.media_src :self, :blob, :https, *extra["media-src"]
    policy.connect_src :self, *extra["connect-src"]
    policy.frame_src :self, "https://challenges.cloudflare.com", *extra["frame-src"]
    policy.worker_src :self, :blob
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self, *extra["form-action"]
    policy.frame_ancestors :self
    policy.report_uri "/csp-reports?surface=admin"
  end
  # Development's tooling (Herb's dev tools) adds scripts of its own: there
  # the policy reports rather than blocks.
  content_security_policy_report_only Rails.env.development? && ENV["CMS_CSP_ENFORCE"].blank?

  before_action :set_current_request_details
  before_action :authenticate
  # After authenticate: the language is the signed-in person's.
  around_action :use_admin_locale, if: :admin_page_request?

  # Authorization runs after authentication so Current.user / Current.api_user
  # are available; declared here last so the before_action order is correct.
  include Authorization

  helper_method :search_term, :settings_screen?

  private

  # Every time the admin shows or reads (schedules, cards, timestamps) is in
  # the site's zone (Settings › General); what's stored stays UTC. Pages only:
  # JSON keeps rendering times in UTC, as the API always has.
  def use_site_time_zone(&)
    Time.use_zone(Site.time_zone, &)
  end

  # The admin's own words in the person's language (AdminLocale); put back
  # after, since I18n.locale outlives the request on its thread.
  def use_admin_locale(&)
    I18n.with_locale(AdminLocale.for(Current.user), &)
  end

  def admin_page_request?
    request.format.html? || request.format.turbo_stream?
  end

  # A list's search term (WordPress's ?s=), or nil.
  # Whether this is a Settings page (Settings::BaseController), which lays its
  # title out above the page and a sidebar (layouts/settings).
  def settings_screen? = false

  def search_term
    params[:s].to_s.strip.presence
  end

  # One page of an index table (Pagination), in @pagination for the
  # numbered pagination under it (pagination_nav). A relation or an array.
  # @page too, unless the controller keeps a page record there: plugins
  # written before numbered pagination read it.
  def paginate(records, per: Pagination::PER_PAGE)
    @pagination = Pagination.new(records, page: params[:page], per: per)
    @page ||= @pagination
    @pagination.records
  end

  def authenticate
    redirect_to sign_in_path unless perform_authentication
  end

  def require_no_authentication
    return unless perform_authentication

    flash[:notice] = "You are already signed in"
    redirect_to pages_path
  end

  def perform_authentication
    Current.session ||= live_session
  end

  # The session the cookie names, unless it has ended (Session::LIFETIME,
  # Session::IDLE_TIMEOUT), in which case it's deleted with its cookie.
  def live_session
    session = Session.find_by_id(cookies.signed[:session_token])
    return session&.tap(&:seen!) unless session&.expired?

    session.destroy
    cookies.delete(:session_token)
    nil
  end

  # Signs `user` in on this browser: a new Session, and its cookie — signed,
  # HttpOnly, SameSite=Lax, Secure over HTTPS, and gone when the session ends.
  def start_session_for(user)
    user.sessions.create!.tap do |record|
      cookies.signed[:session_token] = {
        value: record.id, httponly: true, same_site: :lax, secure: request.ssl?, expires: record.expires_at
      }
    end
  end

  def set_current_request_details
    Current.user_agent = request.user_agent
    Current.ip_address = request.ip
    Current.remote_ip = request.remote_ip
  end
end
