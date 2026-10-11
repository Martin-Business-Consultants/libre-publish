# frozen_string_literal: true

# The delivery API and the frontend's endpoints are off unless the site is
# served over the API (Serving); specs of them turn it on.
module ServingHelpers
  def serve_over_api(mode = "api_only", pages: true)
    Setting.set("general", {"serving" => mode, "api_pages" => pages})
  end
end

RSpec.configure { |config| config.include ServingHelpers }
