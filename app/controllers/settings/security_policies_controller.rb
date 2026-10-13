# frozen_string_literal: true

# Settings › Security policy (SecurityPolicy): the website's
# Content-Security-Policy (off, report only, enforced; the services it
# allows, sources by hand, strict inline scripts), the admin's extra sources,
# and what browsers reported each blocked, to allow in a click.
class Settings::SecurityPoliciesController < Settings::BaseController
  requires_capability "settings:read", only: :show
  requires_capability "settings:write", only: :update

  def show
    @policy = SecurityPolicy.get
    @suggestions = SecurityPolicy.suggestions(@policy)
    @reports = CspReport.open.limit(40).to_a
    @website_header = SecurityPolicy.website_header(nonce: "…", settings: @policy)
    @admin_header = request.content_security_policy&.build(self, "…", %w[script-src]).to_s
  end

  def update
    attributes = params.require(:security_policy).permit(:mode, :strict, presets: [], sources: SecurityPolicy::DIRECTIVES, admin_sources: SecurityPolicy::ADMIN_DIRECTIVES)
    attributes[:presets] ||= [] if params[:security_policy].key?(:presets_sent)
    SecurityPolicy.update(attributes.to_h)
    Event.record("settings.security_policy_updated")
    redirect_to settings_security_policy_path, notice: "Security policy saved"
  end
end
