# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/redirects/import", type: :request do
  let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[redirects:write])) }
  let(:headers) { {"Authorization" => "Bearer #{writer.api_token.token}", "CONTENT_TYPE" => "text/csv"} }

  it "imports a raw CSV body" do
    post "/api/redirects/import", params: "source_path,destination_url\n/a,/b\n", headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("created" => 1, "errored" => 0)
  end

  it "refuses a CSV over the size limit, importing nothing" do
    stub_const("Redirect::Import::MAX_BYTES", 10)

    post "/api/redirects/import", params: "source_path,destination_url\n/a,/b\n", headers: headers

    expect(response).to have_http_status(:content_too_large)
    expect(JSON.parse(response.body)).to include("error" => "too_large")
    expect(Redirect.count).to eq(0)
  end

  it "asks for a CSV when there's none" do
    post "/api/redirects/import", params: "", headers: headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to include("error" => "invalid", "message" => "No CSV supplied")
  end
end
