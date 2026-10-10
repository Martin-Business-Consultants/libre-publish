# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /index" do
    before { sign_in_as user }

    it "is a section of the Account page, listing where you're signed in" do
      get settings_sessions_url
      expect(response).to redirect_to(settings_profile_path(anchor: "sessions"))

      follow_redirect!
      expect(response.body).to include("Sessions", "This device")
    end
  end
end
