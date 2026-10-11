# frozen_string_literal: true

# Fresh recovery codes; the old ones stop working. Rendered once, on the
# Account page.
class Settings::TwoFactors::RecoveryCodesController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization

  # Takes the password, as switching two-factor off does: new codes are a
  # way in.
  def create
    unless Current.user.authenticate(params[:password_challenge].to_s)
      return redirect_to(account_path("two-factor"), alert: "That password isn't right, so the codes weren't changed.")
    end

    @recovery_codes = Current.user.regenerate_recovery_codes!
    Event.record("two_factor.recovery_codes_regenerated", target: Current.user)
    render_account
  end
end
