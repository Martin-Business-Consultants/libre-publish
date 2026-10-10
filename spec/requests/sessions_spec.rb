# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /new" do
    it "returns http success" do
      get sign_in_url
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /sign_in" do
    context "with valid credentials" do
      it "redirects to pages" do
        post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
        expect(response).to redirect_to(pages_url)

        get pages_url
        expect(response).to have_http_status(:success)
      end
    end

    context "the session cookie" do
      # AuthenticationHelpers sign in through a cookie jar kept in the app's
      # env_config, which every request then shares, and a jar already
      # holding a value doesn't send it again. Set it aside for this one.
      around do |example|
        shared = Rails.application.env_config.extract!("action_dispatch.cookies", "rack.request.cookie_hash")
        example.run
      ensure
        Rails.application.env_config.merge!(shared)
      end

      it "is Secure over HTTPS, HttpOnly, SameSite=Lax, and ends with the session, not in 20 years" do
        https!
        post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}

        cookie = Array(response.headers["Set-Cookie"]).join("\n").lines.find { it.start_with?("session_token=") }
        expect(cookie).to match(/;\s*secure/i)
        expect(cookie).to match(/httponly/i)
        expect(cookie).to match(/samesite=lax/i)
        expires = Time.httpdate(cookie[/expires=([^;]+)/i, 1])
        expect(expires).to be_within(1.minute).of(Session::LIFETIME.from_now)
      end
    end

    context "with invalid credentials" do
      before { sign_out }

      it "redirects to the sign in url with an alert" do
        post sign_in_url, params: {email: user.email, password: "SecretWrong1*3"}
        expect(response).to redirect_to(sign_in_url)
        expect(flash[:alert]).to eq("That email or password is incorrect")

        get dashboard_url
        expect(response).to redirect_to(sign_in_url)
      end
    end
  end

  describe "an ended session" do
    before { sign_out }

    it "signs no one in, and is deleted" do
      post sign_in_url, params: {email: user.email, password: "Secret1*3*5*"}
      session = user.sessions.last
      session.update_column(:last_seen_at, (Session::IDLE_TIMEOUT + 1.minute).ago)

      get pages_url

      expect(response).to redirect_to(sign_in_url)
      expect(Session.exists?(session.id)).to be(false)
    end
  end

  describe "DELETE /sign_out" do
    before { sign_in_as user }

    it "signs this device out and lands on sign in" do
      delete session_url(user.sessions.last)
      expect(response).to redirect_to(sign_in_url)

      get settings_sessions_url
      expect(response).to redirect_to(sign_in_url)
    end

    it "signs another device out and stays on the sessions list" do
      other = user.sessions.create!

      delete session_url(other)

      expect(response).to redirect_to(settings_profile_url(anchor: "sessions"))
      expect(user.sessions.exists?(other.id)).to be(false)
      follow_redirect!
      expect(response).to have_http_status(:success)
    end
  end
end
