# frozen_string_literal: true

require "rails_helper"

RSpec.describe Redirect::Matchable do
  def rule(source, destination, **attrs) = Redirect.create!(source_path: source, destination_url: destination, status_code: 301, **attrs)

  it "normalizes the source and knows a wildcard by its trailing /*" do
    expect(rule("old/", "/new")).to have_attributes(source_path: "/old", wildcard: false)
    expect(rule("/blog//*", "/news/*")).to have_attributes(source_path: "/blog/*", wildcard: true)
  end

  it "prefers an exact rule, then the longest wildcard, carrying the tail over" do
    rule("/blog/*", "/news/*")
    rule("/blog/2020/*", "/archive")
    exact = rule("/blog/hello", "/hello", status_code: 302)

    expect(Redirect.match("/blog/hello/")).to eq({redirect: exact, destination: "/hello", status: 302})
    expect(Redirect.match("blog/a/b")[:destination]).to eq("/news/a/b")
    expect(Redirect.match("/blog")[:destination]).to eq("/news")
    expect(Redirect.match("/blog/2020/x")[:destination]).to eq("/archive")
    expect(Redirect.match("/blogger")).to be_nil
  end

  it "ignores inactive rules and counts a real request's hit" do
    rule("/off", "/x", active: false)
    on = rule("/on", "/y")

    expect(Redirect.match("/off")).to be_nil
    expect { Redirect.resolve("/on") }.to change { on.reload.hit_count }.by(1)
    expect { Redirect.match("/on") }.not_to(change { on.reload.hit_count })
  end

  it "refuses a * anywhere but a trailing /*, and a wildcard destination for an exact source" do
    expect(Redirect.new(source_path: "/a*b", destination_url: "/x", status_code: 301)).not_to be_valid
    expect(Redirect.new(source_path: "/a", destination_url: "/x/*", status_code: 301).tap(&:valid?).errors[:destination_url])
      .to include("trailing `/*` requires the source to also end with `/*`")
  end
end
