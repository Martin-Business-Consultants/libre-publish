# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateCheck::Plugins do
  let(:github) { instance_double(UpdateCheck::Github) }

  before do
    allow(InstalledPlugins).to receive_messages(loaded: {"healing" => Pathname("/x/healing"), "hello" => Pathname("/x/hello")},
      versions: {"healing" => "0.2.0", "hello" => "0.1.0"})
    allow(InstalledPlugins).to receive(:repo).with("healing").and_return("acme/healing-theme")
    allow(InstalledPlugins).to receive(:repo).with("hello").and_return(nil)
    allow(UpdateCheck::Github).to receive(:new).with(repo: "acme/healing-theme").and_return(github)
  end

  it "finds the plugins with a newer release than they run" do
    allow(github).to receive(:get).with("releases/latest").and_return("tag_name" => "v0.3.0", "html_url" => "https://github.com/acme/healing-theme/releases/v0.3.0")

    described_class.check_now

    expect(described_class.available).to eq("healing" => "0.3.0")
    expect(described_class.release_url(:healing)).to end_with("v0.3.0")
    expect(described_class.checked_at).to be_within(5.seconds).of(Time.current)
  end

  it "keeps what it knew about a plugin GitHub won't answer for" do
    Setting.set("plugin_updates", "healing" => {"latest_version" => "0.3.0"})
    allow(github).to receive(:get).and_raise(UpdateCheck::Github::Error, "rate limited")

    described_class.check_now

    expect(described_class.available).to eq("healing" => "0.3.0")
  end

  it "says nothing of a plugin that runs its newest release" do
    allow(github).to receive(:get).and_return("tag_name" => "v0.2.0")

    described_class.check_now

    expect(described_class.available).to be_empty
  end
end
