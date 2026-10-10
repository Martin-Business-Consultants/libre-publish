# frozen_string_literal: true

# sign_in_as writes its cookie into the cookie jar Rails.application.env_config
# holds, which outlives the example; it's dropped after each one, so a session
# (and its flash) never carries into the next example's requests.
module AuthenticationHelpers
  extend ActiveSupport::Concern

  def sign_in_as(user)
    session = user.sessions.create!

    request = ActionDispatch::Request.new(Rails.application.env_config)
    cookies = request.cookie_jar
    cookies.signed.permanent[:session_token] = {value: session.id, httponly: true}
  end

  def sign_out
    request = ActionDispatch::Request.new(Rails.application.env_config)
    cookies = request.cookie_jar
    cookies.delete(:session_token)
  end
end

RSpec.configure do |config|
  config.after { Rails.application.env_config.delete("action_dispatch.cookies") }
end
