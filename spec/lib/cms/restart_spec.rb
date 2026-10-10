# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cms::Restart do
  it "migrates and restarts in a process of its own, saying how it went where it's asked to, and in the install's log" do
    report = Pathname(Dir.mktmpdir("restart"))
    report.join("exit_status").write("1\n") # a previous one's

    expect(Process).to receive(:spawn) do |*args, **options|
      expect(args).to include("/bin/bash", "restart", report.join("restart.log").to_s, report.join("exit_status").to_s)
      expect(args.join(" ")).to include("bin/rails db:migrate && bin/rails restart", "tee \"$1\"", "PIPESTATUS[0]")
      expect(options).to include(chdir: Rails.root.to_s, pgroup: true, out: $stdout)
      4242
    end
    expect(Process).to receive(:detach).with(4242)

    described_class.later(report: report)

    expect(report.join("exit_status")).not_to exist
  ensure
    report&.rmtree
  end

  # A Docker image says where its gems are in the environment (the
  # Dockerfile's BUNDLE_PATH, BUNDLE_DEPLOYMENT, BUNDLE_WITHOUT). The restart
  # starts on it, or its bin/rails finds none of them (Bundler::GemNotFound)
  # and the plugin change that asked for it fails.
  it "keeps the environment the install started with, Bundler's settings among them" do
    image = ENV.to_h.merge("BUNDLE_PATH" => "/usr/local/bundle", "BUNDLE_DEPLOYMENT" => "1", "BUNDLE_WITHOUT" => "development:test")
    allow(Bundler).to receive(:original_env).and_return(image)
    started_with = nil
    allow(Process).to receive(:spawn) { started_with = ENV.to_h.slice("BUNDLE_PATH", "BUNDLE_DEPLOYMENT", "BUNDLE_WITHOUT"); 4242 }
    allow(Process).to receive(:detach)
    report = Pathname(Dir.mktmpdir("restart"))

    described_class.later(report: report)

    expect(started_with).to eq("BUNDLE_PATH" => "/usr/local/bundle", "BUNDLE_DEPLOYMENT" => "1", "BUNDLE_WITHOUT" => "development:test")
  ensure
    report&.rmtree
  end
end
