# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Patterns", type: :request do
  let(:admin) { create(:user) }
  let(:cta) { {"type" => "text", "version" => 1, "data" => {"body" => "**Book a consult**"}} }

  before do
    BlockType::Defaults.install!
    sign_in_as admin
  end

  def blocks_param(*blocks) = blocks.each_with_index.to_h { |block, index| [index.to_s, {"_json" => block.to_json}] }

  it "makes, edits and lists a pattern from the block editor" do
    post block_patterns_path, params: {block_pattern: {name: "Call to action", slug: "cta", synced: "1", blocks: blocks_param(cta)}}
    pattern = BlockPattern.find_by!(slug: "cta")
    expect(response).to redirect_to(edit_block_pattern_path(pattern))
    expect(pattern).to have_attributes(synced: true, blocks: [cta])

    get block_patterns_path
    expect(response.body).to include("Call to action", "Synced")

    get edit_page_path(Page.create!(slug: "home", title: "Home", status: "draft", locale: "en").path)
    expect(response.body).to include(%(data-type="pattern:cta"))
  end

  it "inserts an unsynced pattern as copies of its blocks, and a synced one as one block naming it" do
    BlockPattern.create!(name: "Copy me", slug: "copy-me", blocks: [cta, cta])
    BlockPattern.create!(name: "Synced", slug: "synced", synced: true, blocks: [cta])

    get new_content_block_path(type: "pattern:copy-me", scope: "page[blocks]", depth: 1)
    expect(response.body.scan("Book a consult").size).to be >= 2

    get new_content_block_path(type: "pattern:synced", scope: "page[blocks]", depth: 1)
    expect(response.body).to include("synced")
  end

  it "draws a synced pattern's blocks as they are now, wherever it's placed" do
    pattern = BlockPattern.create!(name: "Synced", slug: "synced", synced: true, blocks: [cta])
    page = Page.create!(slug: "home", title: "Home", status: "published", locale: "en",
      blocks: [{"type" => "pattern", "version" => 1, "data" => {"pattern" => "synced"}}])

    expect(page.expanded_blocks.map { it.dig("data", "body") }).to eq(["**Book a consult**"])

    before = DeliveryVersion.current
    pattern.update!(blocks: [cta.deep_merge("data" => {"body" => "Call us"})])
    expect(page.reload.expanded_blocks.map { it.dig("data", "body") }).to eq(["Call us"])
    expect(DeliveryVersion.current).not_to eq(before)

    pattern.destroy!
    expect(page.reload.expanded_blocks).to eq([])
  end

  it "won't hold a synced pattern inside a pattern" do
    pattern = BlockPattern.new(name: "Loop", slug: "loop", blocks: [{"type" => "pattern", "data" => {"pattern" => "loop"}}])

    expect(pattern).not_to be_valid
  end
end
