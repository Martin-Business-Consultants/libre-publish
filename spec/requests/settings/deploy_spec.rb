# frozen_string_literal: true

require "rails_helper"

# Settings › Deploy, with the GitHub method's repository and token (once
# Settings › GitHub, whose address lands here).
RSpec.describe "Settings › Deploy", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "keeps the GitHub method's repository and token, never showing the token back" do
    patch settings_deploy_path, params: {settings: {provider: "github", github_repo: " acme/acme-site ", github_token: "github_pat_secret1234"}}
    expect(response).to redirect_to(settings_deploy_path)

    expect(Deploys::Github.repo).to eq("acme/acme-site")
    expect(Deploys.current).to be_configured
    expect(Deploys.current.target).to eq("acme/acme-site")

    get settings_deploy_path
    expect(response.body).to include("Builds go to", "acme/acme-site", "ends in 1234")
    expect(response.body).not_to include("github_pat_secret1234")
  end

  it "keeps the token when the field is left blank, and clears a repository emptied" do
    Deploys::Github.configure(repo: "acme/old", token: "github_pat_keepme")

    patch settings_deploy_path, params: {settings: {provider: "github", github_repo: "", github_token: ""}}

    expect(Deploys::Github.repo).to eq("")
    expect(Setting.get("github")["token"]).to eq("github_pat_keepme")
  end
end
