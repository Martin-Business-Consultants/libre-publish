# frozen_string_literal: true

# Two-factor on Settings › Account (Settings::AccountScreen): TOTP enrolment
# and disabling.
#
#   GET    /settings/two_factor                 — the Account page, at it
#   POST   /settings/two_factor/activation      — verify a code and switch it on
#                                                 (Settings::TwoFactors::ActivationsController)
#   POST   /settings/two_factor/recovery_codes  — fresh codes
#                                                 (Settings::TwoFactors::RecoveryCodesController)
#   DELETE /settings/two_factor                 — switch it off
#
# Recovery codes are shown once, on the page the activation or regeneration
# renders, and never stored in plaintext.
class Settings::TwoFactorsController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization

  def show
    redirect_to account_path("two-factor")
  end

  def destroy
    Current.user.disable_totp!
    Event.record("two_factor.disabled", target: Current.user)
    redirect_to account_path("two-factor"), notice: "Two-factor authentication disabled"
  end
end
