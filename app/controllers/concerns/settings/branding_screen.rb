# frozen_string_literal: true

# Settings › Branding is one page (settings/brandings/show): appearance, the
# visual identity and the brand context, each a section with its own form.
# The controllers behind those forms render it back on a failed save and
# redirect to its anchor on success; the old pages redirect there too.
module Settings::BrandingScreen
  extend ActiveSupport::Concern

  private

  def render_branding(alert: nil, status: :unprocessable_content)
    prepare_branding
    flash.now[:alert] = alert if alert
    render "settings/brandings/show", status: status
  end

  def prepare_branding
    @workspace = Current.user.can?("settings:read")
    return unless @workspace

    @branding = Branding.current
    @brand_context ||= Settings::BrandsController::FIELDS.index_with { |field| Setting.get(BrandBrief::SETTING_KEY)[field].to_s }
  end
end
