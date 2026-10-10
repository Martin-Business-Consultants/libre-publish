# frozen_string_literal: true

# Switching two-factor on: the code proves the authenticator has the secret.
# Renders the Account page with the new recovery codes — shown this once.
class Settings::TwoFactors::ActivationsController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization

  def create
    user = Current.user
    success, @recovery_codes = user.enable_totp!(params[:code].to_s)

    if success
      Event.record("two_factor.enabled", target: user)
      render_account
    else
      @code_error = "That code is not valid. Check the time on your device and try again."
      render_account failed: "two-factor", status: :unprocessable_content
    end
  end
end
