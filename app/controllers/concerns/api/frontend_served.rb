# frozen_string_literal: true

# What only a frontend elsewhere uses (its status, its builds reporting in,
# approving its delivery): off, 404, unless the site is served over the API
# (Serving, Settings › General).
module Api::FrontendServed
  extend ActiveSupport::Concern

  included do
    before_action :require_frontend_served
  end

  private

  def require_frontend_served
    return if Serving.api?

    render json: {error: "not_found", message: "This site isn't served over the API: Settings › General › How the site is served."}, status: :not_found
  end
end
