# frozen_string_literal: true

# The styleguide for Runwell UI, the shadcn/ui port (app/assets/stylesheets/ui): every
# component in every variant, for whoever draws a screen or a plugin. Development only
# (config/routes.rb), for anyone signed in.
class UiController < ApplicationController
  skip_authorization

  def show
  end
end
