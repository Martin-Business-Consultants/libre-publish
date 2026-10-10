# frozen_string_literal: true

# The email form on Settings › Account (Settings::AccountScreen).
class Settings::EmailsController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization
  before_action :set_user

  def show
    redirect_to account_path("email")
  end

  def update
    if @user.update(user_params)
      redirect_to_success
    else
      render_account failed: "email", status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def user_params
    params.permit(:email, :password_challenge).with_defaults(password_challenge: "")
  end

  def redirect_to_success
    if @user.email_previously_changed?
      resend_email_verification
      redirect_to account_path("email"), notice: "Your email has been changed"
    else
      redirect_to account_path("email")
    end
  end

  def resend_email_verification
    UserMailer.with(user: @user).email_verification.deliver_later
  end
end
