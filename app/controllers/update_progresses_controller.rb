# frozen_string_literal: true

# The update progress modal's poll (UpdateProgress): the CMS updates and
# plugin or theme changes under way, and how the watched ones ended.
class UpdateProgressesController < ApplicationController
  # Anyone signed in: an update restarts the CMS under everyone.
  skip_authorization

  def show
    items = UpdateProgress.new(watching: params[:watching].to_s.split(",")).items
    render json: {items: items.map(&:to_h)}
  end
end
