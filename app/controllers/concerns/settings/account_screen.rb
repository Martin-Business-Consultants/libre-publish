# frozen_string_literal: true

# Your account is one page (settings/profiles/show): name, email, password,
# two-factor, sessions and deleting the account, each a section with its own
# form. The controllers behind those forms render it back on a failed save,
# with the failing section named so only it shows the errors, and redirect
# to its anchor on success. The old per-section pages redirect there too.
module Settings::AccountScreen
  extend ActiveSupport::Concern

  private

  def render_account(failed: nil, status: :ok)
    prepare_account
    @failed = failed
    render "settings/profiles/show", status: status
  end

  def prepare_account
    @user ||= Current.user
    @sessions = @user.sessions.order(created_at: :desc)
    # Its own copy: @user may carry a failed save's changes and errors.
    @totp = User.find(@user.id)
    @totp.setup_totp_secret! if @totp.totp_secret.blank? && !@totp.totp_enabled?
  end

  def account_path(section) = settings_profile_path(anchor: section)
end
