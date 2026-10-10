# frozen_string_literal: true

# Where you're signed in is a section of Settings › Account.
class Settings::SessionsController < Settings::BaseController
  include Settings::AccountScreen

  skip_authorization

  def index
    redirect_to account_path("sessions")
  end
end
