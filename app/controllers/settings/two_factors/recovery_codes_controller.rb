# frozen_string_literal: true

# Fresh recovery codes; the old ones stop working. Rendered once, on the
# Account page.
class Settings::TwoFactors::RecoveryCodesController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization

  def create
    @recovery_codes = Current.user.regenerate_recovery_codes!
    Event.record("two_factor.recovery_codes_regenerated", target: Current.user)
    render_account
  end
end
