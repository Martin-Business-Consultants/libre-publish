# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentDiff do
  def diff(payload, base) = described_class.new(payload, base).call[:fields]

  it "tells blocks added, removed, moved and changed apart by id" do
    before = [
      {"id" => "a", "type" => "hero", "data" => {"heading" => "Hi"}},
      {"id" => "b", "type" => "text", "data" => {"body" => "One"}},
      {"id" => "c", "type" => "cta",  "data" => {}}
    ]
    after = [
      {"id" => "b", "type" => "text", "data" => {"body" => "Two"}},
      {"id" => "a", "type" => "hero", "data" => {"heading" => "Hi"}},
      {"id" => "d", "type" => "faq",  "data" => {}}
    ]

    rows = diff({"blocks" => after}, {"blocks" => before}).first[:blocks]

    expect(rows.map { [it[:op], it[:id]] }).to eq([["changed_and_moved", "b"], ["moved", "a"], ["added", "d"], ["removed", "c"]])
    expect(rows.first[:fields]).to eq([{key: "body", op: "changed", before: "One", after: "Two"}])
  end

  it "pairs blocks without ids by type, in order" do
    before = [{"type" => "text", "data" => {"body" => "x"}}]
    after = [{"type" => "text", "data" => {"body" => "y"}}]

    expect(diff({"blocks" => after}, {"blocks" => before}).first[:blocks].map { it[:op] }).to eq(["changed"])
  end

  it "diffs objects key by key, and nested values whole" do
    entries = diff({"frontmatter" => {"a" => 1, "c" => {"x" => 1}}}, {"frontmatter" => {"a" => 2, "b" => "gone"}}).first[:entries]

    expect(entries.map { [it[:key], it[:op]] }).to eq([["a", "changed"], ["b", "removed"], ["c", "added"]])
    expect(entries.last[:after]).to eq(JSON.pretty_generate({"x" => 1}))
  end

  it "shows short text whole and long text line by line, unchanged runs collapsed" do
    expect(diff({"title" => "New"}, {"title" => "Old"})).to eq([{key: "title", kind: "text", before: "Old", after: "New"}])

    before = (1..10).map { "line #{it}" }.join("\n")
    after = before.sub("line 9", "line nine")
    lines = diff({"body_markdown" => after}, {"body_markdown" => before}).first[:lines]

    expect(lines.first).to eq({op: "skip", count: 5})
    expect(lines.select { it[:op] != "eq" && it[:op] != "skip" }).to eq([{op: "del", text: "line 9"}, {op: "add", text: "line nine"}])
  end
end
