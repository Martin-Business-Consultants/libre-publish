# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeneralSettings do
  it "saves the form's fields, keeping an unknown time zone out, and records what changed" do
    Setting.set("general", {"title" => "Old", "timezone" => "Europe/London"})

    GeneralSettings.update("title" => "New", "timezone" => "Mars/Olympus", "public_origins_raw" => "https://a.test,\n https://b.test")

    expect(Setting.get("general")).to include("title" => "New", "timezone" => "Europe/London",
      "public_origins" => %w[https://a.test https://b.test])
    expect(AuditLog.where(action: "settings.general_updated").last.metadata["fields"]).to eq(%w[title public_origins])
  end

  it "serves exactly the collections ticked, and an unknown mode changes nothing" do
    posts = Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    team = Collection.create!(slug: "team", name: "Team", schema: {"fields" => []}, api_enabled: true)

    GeneralSettings.update("serving" => "nonsense", "api_pages" => "1", "api_collections" => ["", "posts"])

    expect(posts.reload.api_enabled).to be(true)
    expect(team.reload.api_enabled).to be(false)
    expect(Setting.get("general")).to include("api_pages" => true)
    expect(Setting.get("general")).not_to have_key("serving")
  end

  it "records nothing when nothing changed" do
    Setting.set("general", {"title" => "Same"})

    expect { GeneralSettings.update("title" => "Same") }.not_to(change { AuditLog.where(action: "settings.general_updated").count })
  end
end
