# frozen_string_literal: true

require "rails_helper"

# Settings › Media (ImageLimits): how heavy an image on the website may be.
RSpec.describe "Settings › Media", type: :request do
  before { sign_in_as create(:user) }

  it "starts from sane defaults, and saves a site's own, within reason" do
    get settings_media_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Image limits", %(value="750"), %(value="2560"))
    expect(ImageLimits.optimize_uploads?).to be(true)

    patch settings_media_path, params: {media: {max_kb: "500", max_side: "1920", optimize_uploads: "0"}}
    expect(response).to redirect_to(settings_media_path)
    expect([ImageLimits.max_bytes, ImageLimits.max_side, ImageLimits.optimize_uploads?]).to eq([500.kilobytes, 1920, false])

    patch settings_media_path, params: {media: {max_kb: "5", max_side: "99999", optimize_uploads: "1"}}
    expect([ImageLimits.max_kb, ImageLimits.max_side, ImageLimits.optimize_uploads?]).to eq([750, 2560, true])
  end
end
