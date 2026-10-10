# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools › Search and replace", type: :request do
  let(:admin) { create(:user) }

  before do
    BlockType::Defaults.install!
    page
    global
    sign_in_as admin
  end

  let(:page) do
    Page.create!(slug: "about", title: "About Acme Ltd", status: "published", locale: "en",
      blocks: [{"id" => "acme-1", "type" => "text", "version" => 1, "data" => {"body" => "Acme Ltd builds. acme ltd grows."}}],
      seo: {"meta_description" => "Acme Ltd, since 1990"})
  end
  let(:global) { Global.create!(slug: "footer", name: "Footer", schema: {"fields" => [{"name" => "note", "type" => "string"}]}, data: {"note" => "© Acme Ltd"}) }

  it "finds a phrase across pages and globals, ignoring case unless asked" do
    get tools_search_replace_path(term: "acme ltd")
    expect(response.body).to include("5 matches in 2 records", "About Acme Ltd", "Footer")

    get tools_search_replace_path(term: "acme ltd", case_sensitive: "1")
    expect(response.body).to include("1 match in 1 record")
  end

  it "replaces it everywhere, leaving a block's own keys and the slugs alone" do
    post tools_search_replace_path, params: {term: "Acme Ltd", replacement: "Acme Inc.", case_sensitive: "1"}

    expect(flash[:notice]).to eq("Replaced 4 matches in 2 records.")
    page.reload
    expect(page.title).to eq("About Acme Inc.")
    expect(page.blocks.first).to include("id" => "acme-1", "type" => "text", "data" => {"body" => "Acme Inc. builds. acme ltd grows."})
    expect(page.seo["meta_description"]).to eq("Acme Inc., since 1990")
    expect(page.slug).to eq("about")
    expect(global.reload.data["note"]).to eq("© Acme Inc.")
    expect(AuditLog.where(action: "content.replaced")).to exist
  end

  it "needs the publish permissions to replace" do
    sign_in_as create(:user, admin: false, role: create(:role, permissions: %w[pages:read pages:write]))

    post tools_search_replace_path, params: {term: "Acme Ltd", replacement: "X"}

    expect(page.reload.title).to eq("About Acme Ltd")
  end
end
