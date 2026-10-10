# frozen_string_literal: true

# Settings › Account: the one page for your own account (Settings::AccountScreen),
# and the name and delete forms on it.
class Settings::ProfilesController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization
  before_action :set_user

  def show
    prepare_account
  end

  def update
    if @user.update(user_params)
      redirect_to account_path("profile"), notice: "Your profile has been updated"
    else
      render_account failed: "profile", status: :unprocessable_content
    end
  end

  def destroy
    if @user.authenticate(params[:password_challenge] || "")
      @user.destroy!
      cookies.delete(:session_token)
      Current.session = nil
      redirect_to sign_in_path, notice: "Your account has been deleted"
    else
      @user.errors.add(:password_challenge, "is invalid")
      render_account failed: "delete", status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def user_params
    params.permit(:name)
  end
end
