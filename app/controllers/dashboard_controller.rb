# frozen_string_literal: true

# The API's use and the frontend, and whatever plugins put on the dashboard
# (the :dashboard slot).
class DashboardController < ApplicationController
  skip_authorization

  def index
  end
end
