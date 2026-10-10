# frozen_string_literal: true

require "rails_helper"

# One audit vocabulary (STYLE.md, Events): the admin and the API record the
# same act under the same action and metadata, and only `via: "api"` tells
# them apart.
RSpec.describe "Audit vocabulary", type: :request do
  let(:admin) { create(:user) }
  let(:api) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  # [action, metadata without via] of the rows a block writes.
  def rows_from
    from = AuditLog.maximum(:id).to_i
    yield
    AuditLog.where("id > ?", from).order(:id).map { [it.action, it.metadata.except("via")] }
  end

  def admin_rows(&)
    sign_in_as admin
    rows_from(&)
  end

  it "names a block type's delete the same from both" do
    %w[one two].each { BlockType.create!(slug: it, label: it, fields: [], defaults: {}, version: 1) }

    from_api = rows_from { delete "/api/block_types/one", headers: api }
    from_admin = admin_rows { delete "/block_types/two" }

    expect(from_api.map(&:first)).to eq(["block_type.deleted"])
    expect(from_admin.map(&:first)).to eq(["block_type.deleted"])
  end

  it "records a Build board publish the same from both" do
    collection = Collection.create!(slug: "specials", name: "Specials",
      schema: {"fields" => [{"name" => "active", "label" => "Active", "type" => "boolean"}]},
      build_config: {"field" => "active", "also_publish" => true})
    %w[a b].each { collection.entries.create!(slug: it, title: it, status: "draft", locale: "en", frontmatter: {"active" => false}) }

    from_api = rows_from { patch "/api/collections/specials/entries/a/move", params: {on: true}, headers: api, as: :json }
    from_admin = admin_rows { post "/collections/specials/entries/b/placement", params: {column: "on"} }

    expect(from_api.map { [it[0], it[1].except("slug")] }).to eq(from_admin.map { [it[0], it[1].except("slug")] })
    expect(from_api.first).to eq(["entry.published", {"collection" => "specials", "slug" => "a", "fields" => ["active"], "to" => true, "from" => "draft"}])
  end

  it "records deploy settings and Deploy now the same from both" do
    from_api = rows_from do
      patch "/api/deploy", params: {deploy: {url: "https://hooks.example.test/a", provider: "build_hook"}}, headers: api, as: :json
      post "/api/deploy/trigger", headers: api
    end
    from_admin = admin_rows do
      patch "/settings/deploy", params: {settings: {url: "https://hooks.example.test/b", provider: "build_hook", paused: "0"}}
      post "/settings/deploy/trigger"
    end

    expect(from_api).to eq(from_admin)
    expect(from_admin).to eq([["settings.deploy_updated", {"url_set" => true, "paused" => false, "provider" => "build_hook"}],
      ["settings.deploy_triggered", {}]])
  end

  it "records a sitemap row edit from both" do
    page = Page.create!(slug: "about", title: "About", status: "published", locale: "en")

    from_api = rows_from { patch "/api/sitemap/page/#{page.id}", params: {entry: {sitemap_priority: 0.4}}, headers: api, as: :json }
    from_admin = admin_rows { patch "/sitemap/page/#{page.id}", params: {entry: {sitemap_priority: 0.6}} }

    expect(from_api).to eq(from_admin)
    expect(from_admin).to eq([["sitemap.entry_updated", {"source" => "page"}]])
  end
end
