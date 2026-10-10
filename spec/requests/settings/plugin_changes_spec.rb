# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Installing plugins from Settings › Plugins", type: :request do
  let(:admin) { create(:user) }

  it "offers admins a repository to install, and starts it" do
    sign_in_as admin

    get settings_plugins_path
    expect(response.body).to include("Add a plugin", "owner/cms-thing")

    post settings_plugins_installations_path, params: {repo: "acme/cms-thing"}

    expect(response).to redirect_to(settings_plugins_path)
    expect(flash[:notice]).to match(/Installing acme\/cms-thing/)
    expect(PluginChange.last).to have_attributes(repo: "acme/cms-thing", requested_by: admin)

    get settings_plugins_path
    expect(response.body).to include("Installing acme/cms-thing", 'data-controller="refresh"')
  end

  it "says what's wrong with a repository" do
    sign_in_as admin

    post settings_plugins_installations_path, params: {repo: "nonsense"}

    expect(flash[:alert]).to match(/GitHub repository/)
    expect(PluginChange.count).to eq(0)
  end

  it "is for admins only, since it puts code on the server" do
    editor = create(:user, admin: false)
    editor.role.update!(permissions: %w[settings:read settings:write])
    sign_in_as editor

    get settings_plugins_path
    expect(response.body).not_to include("Add a plugin")

    post settings_plugins_installations_path, params: {repo: "acme/cms-thing"}
    expect(response).not_to redirect_to(settings_plugins_path)
    expect(PluginChange.count).to eq(0)
  end
end
