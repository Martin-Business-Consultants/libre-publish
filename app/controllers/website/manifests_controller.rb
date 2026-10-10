# frozen_string_literal: true

# The website's web app manifest (/site.webmanifest): the name and icons a
# phone uses when someone adds the site to their home screen, drawn by the
# theme's website/manifest.
class Website::ManifestsController < ActionController::Base
  before_action { prepend_view_path Website.theme.views }

  def show
    return head(:not_found) unless Website.draws?("website/manifest")

    expires_in 1.hour, public: true
    render "website/manifest", formats: :json, content_type: "application/manifest+json"
  end
end
