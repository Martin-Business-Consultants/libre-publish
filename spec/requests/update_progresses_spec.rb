# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The update progress modal", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  def running_change(**attributes)
    PluginChange.new(action: "update", key: "forms", repo: "Martin-Business-Consultants/cms-forms", from_version: "1.1.0",
      status: "running", requested_by: admin, **attributes).tap { it.save!(validate: false) }
  end

  it "opens on every admin page while an update runs, and not otherwise" do
    get dashboard_path
    expect(response.body).to include(%(data-update-progress-running-value="false"))

    running_change(to_version: "9.9.9")
    get dashboard_path
    expect(response.body).to include(%(data-update-progress-running-value="true"))
  end

  it "says how far each update is, and how a watched one ended" do
    change = running_change(to_version: "9.9.9")
    upgrade = Upgrade.new(from_version: "1.0.0", to_version: "1.1.0", via: "in_place", status: "running", requested_by: admin)
    upgrade.save!(validate: false)
    allow(Upgrade).to receive(:settle_running)

    get update_progress_path
    items = response.parsed_body["items"].index_by { it["id"] }
    expect(items["plugin_change-#{change.id}"]).to include("percent" => 35, "step" => "Downloading forms 9.9.9", "status" => "running")
    expect(items["upgrade-#{upgrade.id}"]).to include("title" => "Updating the CMS to 1.1.0", "status" => "running")
    expect(items["upgrade-#{upgrade.id}"]["percent"]).to be_between(5, 95)

    change.fail_with("It didn't load.")
    upgrade.update!(status: "succeeded", finished_at: Time.current)

    get update_progress_path(watching: "plugin_change-#{change.id},upgrade-#{upgrade.id},nonsense")
    items = response.parsed_body["items"].index_by { it["id"] }
    expect(items["plugin_change-#{change.id}"]).to include("status" => "failed", "message" => "It didn't load.", "percent" => 100)
    expect(items["upgrade-#{upgrade.id}"]).to include("status" => "succeeded", "step" => "Done")

    get update_progress_path
    expect(response.parsed_body["items"]).to be_empty
  end

  it "estimates a CMS update by time, never reaching the end until it's done" do
    upgrade = Upgrade.new(via: "in_place", status: "running", to_version: "1.1.0", created_at: 1.hour.ago)
    expect(upgrade.progress.first).to eq(94).or eq(95)
  end
end
