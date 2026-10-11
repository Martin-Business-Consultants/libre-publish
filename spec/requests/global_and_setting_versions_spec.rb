# frozen_string_literal: true

require "rails_helper"

# Globals and the settings people edit keep every change, as pages do.
RSpec.describe "Version history for globals and settings", type: :request do
  let(:admin) { create(:user) }

  before { sign_in_as admin }

  it "keeps a global's every change, compares one with now, and restores it" do
    nav = Global.create!(slug: "navigation", name: "Navigation", schema: {"fields" => []}, data: {"items" => [{"label" => "Home"}]})
    nav.update!(data: {"items" => [{"label" => "Home"}, {"label" => "Shop"}]})
    first = nav.versions.order(:id).first

    expect(nav.versions.count).to eq(2)
    get global_versions_path("navigation")
    expect(response.body).to include("Revisions of “Navigation”")

    get global_version_path("navigation", first)
    expect(response.body).to include("Restore this version")

    post global_version_restoration_path("navigation", first)
    expect(nav.reload.data["items"].map { it["label"] }).to eq(["Home"])

    get edit_global_path("navigation")
    expect(response.body).to include("Revisions (3)")
  end

  it "won't restore the Scripts global for someone without globals:scripts" do
    editor = create(:user, admin: false, role: create(:role, permissions: Permissions.defaults_for(:editor)))
    scripts = Global.create!(slug: "scripts", name: "Scripts", schema: {"fields" => []}, data: {"items" => [{"head" => "<script>evil()</script>"}]})
    scripts.update!(data: {"items" => []})
    sign_in_as editor

    post global_version_restoration_path("scripts", scripts.versions.order(:id).first)
    expect(scripts.reload.data["items"]).to eq([])
  end

  it "keeps the settings people edit, never a secret, and restores one keeping the secret it has now" do
    Setting.set("general", {"title" => "Old Mill"})
    Setting.set("general", {"title" => "Old Mill Bakery", "smtp_password" => "s3cret"})
    Setting.set("updates", {"latest_version" => "9.9.9"})

    expect(SettingVersion.where(key: "updates")).to be_empty
    expect(SettingVersion.pluck(:data).to_s).not_to include("s3cret")

    get settings_histories_path
    expect(response.body).to include("Settings history", "General")

    first = SettingVersion.where(key: "general").order(:id).first
    post restore_settings_history_path(first)
    expect(Setting.get("general")).to include("title" => "Old Mill", "smtp_password" => "s3cret")
  end
end
