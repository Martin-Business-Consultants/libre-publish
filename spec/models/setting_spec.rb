# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setting do
  describe ".get / .set" do
    it "returns {} for an unknown key" do
      expect(described_class.get("never-set")).to eq({})
    end

    it "round-trips a hash" do
      described_class.set("api", provider: "anthropic", default_model: "claude-sonnet-4-6")
      expect(described_class.get("api")).to eq("provider" => "anthropic", "default_model" => "claude-sonnet-4-6")
    end

    it "deep-merges on subsequent sets" do
      described_class.set("api", provider: "anthropic")
      described_class.set("api", default_model: "claude-haiku-4-5")
      expect(described_class.get("api")).to include("provider" => "anthropic", "default_model" => "claude-haiku-4-5")
    end
  end

  describe ".set with a block" do
    it "merges what the block makes of the data as it is now" do
      Setting.set("deploy", {"pending_changes" => [1], "paused" => false})

      Setting.set("deploy") { |data| {"pending_changes" => data["pending_changes"] + [2]} }

      expect(Setting.get("deploy")).to eq("pending_changes" => [1, 2], "paused" => false)
    end

    it "reads past a copy of the row loaded before another write" do
      Setting.set("deploy", {"pending_changes" => [1]})
      stale = Setting.find_by!(key: "deploy")
      Setting.set("deploy") { |data| {"pending_changes" => data["pending_changes"] + [2]} }

      Setting.set("deploy") { |data| {"pending_changes" => data["pending_changes"] + [3]} }

      expect(Setting.get("deploy")["pending_changes"]).to eq([1, 2, 3])
      expect(stale.data["pending_changes"]).to eq([1])
    end
  end

  describe ".delete_key" do
    it "removes the row" do
      described_class.set("scratch", a: 1)
      expect(described_class.delete_key("scratch")).to eq(1)
      expect(described_class.get("scratch")).to eq({})
    end
  end

  # (One save each: inside a spec's transaction, commit callbacks run for a
  # record's first save only.)
  describe "a change to what the site shows from Settings › General" do
    before { allow(Deploys).to receive(:schedule_later) }

    it "rebuilds or purges the site, tagged site and sitemap" do
      Setting.set("general", {"phone" => "555-0100"})

      general = Setting.find_by!(key: "general")
      expect(Deploys).to have_received(:schedule_later).with(reason: "settings.general_updated", subject: general).once
      expect(Deploys::Change.from("settings.general_updated", general)["tags"]).to eq(%w[site sitemap])
    end

    it "leaves the site alone for settings it doesn't show" do
      Setting.set("general", {"email_from_name" => "Robot"})
      Setting.set("deploy", {"paused" => true})

      expect(Deploys).not_to have_received(:schedule_later)
    end
  end
end
