# frozen_string_literal: true

require "rails_helper"

# The public API (docs/compatibility.md, Cms::PublicApi) against its
# snapshot in spec/fixtures/contracts/public_api.json. A change that breaks a
# caller fails here: deprecate instead (Cms.deprecator) and remove it in the
# next major version. An addition fails too, until `bin/rails
# cms:public_api` writes it into the snapshot, so nothing joins the public API
# by accident.
RSpec.describe "Public API contract" do
  let(:snapshot) { JSON.parse(Rails.root.join("spec/fixtures/contracts/public_api.json").read) }
  let(:now) { Cms::PublicApi.snapshot }

  it "takes every call it took before" do
    breaks = Cms::PublicApi.breaks(snapshot, now)

    expect(breaks).to be_empty, "These break plugins, themes or API clients (docs/compatibility.md):\n  #{breaks.join("\n  ")}"
  end

  it "has nothing new the snapshot doesn't hold" do
    added = (now["ruby"].keys - snapshot["ruby"].keys) + (now["routes"] - snapshot["routes"])
    changed = now["ruby"].select { |name, params| snapshot["ruby"].key?(name) && snapshot["ruby"][name] != params }.keys

    expect(added + changed).to be_empty, "New to the public API; if meant, run bin/rails cms:public_api:\n  #{(added + changed).join("\n  ")}"
  end

  describe "what counts as breaking" do
    def check(old, now) = Cms::PublicApi.incompatible(old.map { it.map(&:to_s) }, now.map { it.map(&:to_s) })

    it "allows a new optional argument or keyword" do
      expect(check([[:req, :key]], [[:req, :key], [:opt, :more]])).to be_nil
      expect(check([[:req, :key], [:key, :a]], [[:req, :key], [:key, :a], [:key, :b]])).to be_nil
    end

    it "refuses a new required argument or keyword, or a keyword taken away" do
      expect(check([[:req, :key]], [[:req, :key], [:req, :more]])).to eq("needs more arguments")
      expect(check([[:req, :key]], [[:req, :key], [:keyreq, :b]])).to eq("needs b: now")
      expect(check([[:key, :a]], [[:key, :b]])).to eq("no longer takes a:")
      expect(check([[:key, :a]], [[:keyrest, :rest]])).to be_nil
      expect(check([[:opt, :a]], [])).to eq("takes fewer arguments")
    end
  end

  it "registers a plugin made for a newer core, leaving out what this one doesn't know" do
    expect { Cms::Plugins.register(:from_the_future, name: "Future", version: "1.0.0", description: "x", sparkles: true) }.not_to raise_error
    expect(Cms::Plugins.manifests[:from_the_future].name).to eq("Future")
  ensure
    Cms::Plugins.manifests.delete(:from_the_future)
  end
end
