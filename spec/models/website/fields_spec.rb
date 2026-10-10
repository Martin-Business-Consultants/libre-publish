# frozen_string_literal: true

require "rails_helper"

RSpec.describe Website::Fields do
  let(:fields) do
    [
      {"name" => "heading", "type" => "string"},
      {"name" => "items", "type" => "repeater", "of" => [{"name" => "title", "type" => "string"}]},
      {"name" => "cta", "type" => "group", "of" => [{"name" => "label", "type" => "string"}]},
      {"name" => "tags", "type" => "string_list"}
    ]
  end

  it "reads declared fields, nil when the record never set one" do
    data = described_class.new({"heading" => "Hello"}, fields, name: "hero")

    expect(data.heading).to eq("Hello")
    expect(data[:heading]).to eq("Hello")
    expect(data.cta.label).to be_nil
    expect(data.items).to eq([])
    expect(data.tags).to eq([])
  end

  it "reads repeaters and groups as fields of their own" do
    data = described_class.new({"items" => [{"title" => "One"}], "cta" => {"label" => "Go"}}, fields, name: "hero")

    expect(data.items.first.title).to eq("One")
    expect(data.cta.label).to eq("Go")
  end

  it "raises for a field the schema doesn't declare, naming the record and what it has" do
    data = described_class.new({"headng" => "Hello"}, fields, name: "hero")

    expect { data.headng }.to raise_error(Website::Fields::Unknown, /hero has no field "headng" \(it has heading, items, cta(,)? and tags\)/)
    expect { data.items.first&.subtitle }.not_to raise_error
    expect { described_class.new({"items" => [{}]}, fields, name: "hero").items.first.subtitle }
      .to raise_error(Website::Fields::Unknown, /hero.items\[0\] has no field "subtitle"/)
  end
end
