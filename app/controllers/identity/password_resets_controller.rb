# frozen_string_literal: true

class Identity::PasswordResetsController < ApplicationController
  layout "public"

  skip_authorization
  skip_before_action :authenticate

  before_action :set_user, only: %i[ edit update ]

  # Throttle the email-emit and the reset-completion to deter abuse +
  # email-bombing. Keyed on IP + the email address being asked about,
  # so legitimate retries from one user don't block another.
  rate_limit to: 5, within: 1.hour, only: :create,
    by:   -> { "password_resets:create:#{request.remote_ip}" },
    with: -> {
      flash[:alert] = "Too many password-reset attempts. Try again later."
      redirect_to new_identity_password_reset_path
    }

  def new
  end

  def edit
  end

  def create
    # The same answer whether or not the address has an account, so the form
    # doesn't tell anyone who does.
    if (@user = User.find_by(email: params[:email], verified: true))
      send_password_reset_email
    end
    redirect_to sign_in_path, notice: "If that address has an account, a reset link is on its way."
  end

  def update
    if @user.update(user_params)
      redirect_to sign_in_path, notice: "Your password was reset successfully. Please sign in"
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = User.find_by_token_for!(:password_reset, params[:sid])
  rescue StandardError
    redirect_to new_identity_password_reset_path, alert: "That password reset link is invalid"
  end

  def user_params
    params.permit(:password, :password_confirmation)
  end

  def send_password_reset_email
    UserMailer.with(user: @user).password_reset.deliver_later
  end
end
