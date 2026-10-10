# frozen_string_literal: true

require "rails_helper"

# Every /api error is JSON in one shape, {"error": "<code>", "message": …}
# (Api::ErrorResponses, ApiExceptions) — including the ones that used to
# reach Rails' exception page. The bodies the API already answered keep
# their bytes.
RSpec.describe "API error responses", type: :request do
  let(:admin) { create(:user) }
  let(:token) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  def json = JSON.parse(response.body)

  it "answers a missing parameter with 400" do
    post "/api/pages", headers: token, params: {}, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(json["error"]).to eq("bad_request")
    expect(json["message"]).to include("page")
  end

  it "answers a body that isn't JSON with 400" do
    post "/api/pages", headers: token.merge("Content-Type" => "application/json"), params: "{not json"

    expect(response).to have_http_status(:bad_request)
    expect(json["error"]).to eq("bad_request")
  end

  it "answers a format the endpoint doesn't serve with 406" do
    get "/api/v1/redirects.xml", headers: token

    expect(response).to have_http_status(:not_acceptable)
    expect(json["error"]).to eq("not_acceptable")
  end

  it "answers a record that changed under the request with 409" do
    allow(Page).to receive(:live).and_raise(ActiveRecord::StaleObjectError.new(Page.new, "update"))

    get "/api/v1/pages", headers: token

    expect(response).to have_http_status(:conflict)
    expect(json["error"]).to eq("conflict")
  end

  it "answers an unexpected error with a JSON 500 and no backtrace, and reports it" do
    allow(Rails.application.config).to receive(:consider_all_requests_local).and_return(false)
    allow(Page).to receive(:live).and_raise(RuntimeError, "secret detail")
    expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), hash_including(handled: true))

    get "/api/v1/pages", headers: token

    expect(response).to have_http_status(:internal_server_error)
    expect(json).to eq("error" => "internal_error", "message" => "Something went wrong on the CMS.")
  end

  it "raises an unexpected error where requests are local (development, test)" do
    allow(Page).to receive(:live).and_raise(RuntimeError, "boom")

    expect { get "/api/v1/pages", headers: token }.to raise_error(RuntimeError, "boom")
  end

  it "keeps the bodies it already answered with: not_found, invalid, forbidden with its capability" do
    get "/api/pages/nope", headers: token
    expect(response).to have_http_status(:not_found)
    expect(json.keys).to eq(%w[error message])
    expect(json["error"]).to eq("not_found")

    reader = create(:user, admin: false, role: create(:role, permissions: %w[pages:read]))
    post "/api/pages", headers: {"Authorization" => "Bearer #{reader.api_token.token}"},
      params: {page: {slug: "x", title: "X"}}, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(json).to eq("error" => "forbidden", "capability" => "pages:write")
  end

  it "answers an /api path no route matches with JSON, and leaves other paths to the public pages" do
    # As in production: no detailed exception pages.
    env_config = Rails.application.env_config.merge("action_dispatch.show_detailed_exceptions" => false)
    allow(Rails.application).to receive(:env_config).and_return(env_config)

    get "/api/no-such-thing", headers: token

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
    expect(json).to eq("error" => "not_found", "message" => "Not Found")

    get "/no-such-thing"
    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end
end
