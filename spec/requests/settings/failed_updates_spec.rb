# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Clearing failed updates", type: :request do
  let(:admin) { create(:user) }
  let(:writer) { create(:user, admin: false, role: create(:role, permissions: %w[settings:read settings:write])) }

  def upgrade(status)
    Upgrade.new(from_version: "1.0.0", to_version: "1.1.0", via: "in_place", status: status, requested_by: admin).tap { it.save!(validate: false) }
  end

  def change(status)
    PluginChange.new(action: "update", key: "forms", repo: "acme/cms-forms", from_version: "1.0.0", to_version: "1.1.0",
      status: status, requested_by: admin).tap { it.save!(validate: false) }
  end

  it "clears the CMS updates that failed from Settings › Updates, and only those" do
    failed, succeeded = upgrade("failed"), upgrade("succeeded")
    sign_in_as admin

    get settings_updates_path
    expect(response.body).to include("Clear failed updates")

    delete settings_updates_failures_path
    expect(response).to redirect_to(settings_updates_path)
    expect(Upgrade.exists?(failed.id)).to be(false)
    expect(Upgrade.exists?(succeeded.id)).to be(true)

    get settings_updates_path
    expect(response.body).not_to include("Clear failed updates")
  end

  it "clears the plugin and theme changes that failed, with their restart reports" do
    failed, running = change("failed"), change("running")
    FileUtils.mkdir_p(failed.report)
    allow(PluginChange).to receive(:reconcile)
    sign_in_as admin

    get settings_plugins_path
    expect(response.body).to include("Clear failed updates")

    delete settings_plugins_failures_path
    expect(response).to redirect_to(settings_plugins_path)
    expect(PluginChange.exists?(failed.id)).to be(false)
    expect(PluginChange.exists?(running.id)).to be(true)
    expect(failed.report).not_to exist
  end

  it "takes an admin" do
    upgrade("failed")
    sign_in_as writer

    delete settings_updates_failures_path
    expect(flash[:alert]).to match(/permission/)
    expect(Upgrade.where(status: "failed").count).to eq(1)
  end
end
