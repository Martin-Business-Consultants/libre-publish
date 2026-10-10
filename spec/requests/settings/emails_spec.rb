# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::Emails", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in_as user
  end

  describe "GET /settings/email" do
    it "is a section of the Account page" do
      get settings_email_url
      expect(response).to redirect_to(settings_profile_path(anchor: "email"))
    end
  end

  describe "PATCH /update" do
    context "with valid password challenge" do
      it "updates the email and goes back to its section" do
        patch settings_email_url, params: {email: "new_email@hey.com", password_challenge: "Secret1*3*5*"}
        expect(response).to redirect_to(settings_profile_path(anchor: "email"))
        expect(flash[:notice]).to eq("Your email has been changed")
      end
    end

    context "with invalid password challenge" do
      it "does not update the email and returns unprocessable entity" do
        patch settings_email_url, params: {email: "new_email@hey.com", password_challenge: "SecretWrong1*3"}
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Password challenge is invalid")
        expect(response.body).not_to include("SecretWrong1*3")
        expect(response.body.scan("Password challenge is invalid").size).to eq(1)
      end
    end
  end
end
