# frozen_string_literal: true

# The password form on Settings › Account (Settings::AccountScreen).
class Settings::PasswordsController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization
  before_action :set_user

  def show
    redirect_to account_path("password")
  end

  def update
    if @user.update(user_params)
      redirect_to account_path("password"), notice: "Your password has been changed"
    else
      render_account failed: "password", status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def user_params
    params.permit(:password, :password_confirmation, :password_challenge).with_defaults(password_challenge: "")
  end
end
