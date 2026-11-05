# frozen_string_literal: true

require "rails_helper"

# /files/<key>/<name>: an asset's file at the address the delivery API gives
# sites (Asset::Delivery), as the Go core serves them and @librepublish/astro
# copies into a site's build.
RSpec.describe "Delivered files", type: :request do
  let(:asset) {
    Asset.create!(folder: "/", alt: "Icon", file: {io: File.open(Rails.root.join("public/icon.png")), filename: "icon.png", content_type: "image/png"})
  }

  it "gives an asset's URLs at /files, each leading to the file or its rendition, to anyone" do
    delivery = asset.delivery
    expect(delivery["url"]).to match(%r{\Ahttps?://[^/]+/files/#{asset.file.blob.key}/icon\.png\z})
    expect(delivery["variants"]["w640"]).to end_with("/files/#{asset.file.blob.key}/w640/icon.png") if delivery["variants"].any?

    get URI(delivery["url"]).path
    expect(response).to redirect_to(%r{/rails/active_storage/blobs/})

    get "/files/#{asset.file.blob.key}/w640/icon.png"
    expect(response).to redirect_to(%r{/rails/active_storage/representations/})
  end

  it "serves only assets' files, and only the renditions it makes" do
    get "/files/#{asset.file.blob.key}/w333/icon.png"
    expect(response).to have_http_status(:not_found)

    other = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("secret"), filename: "backup.tar.gz")
    get "/files/#{other.key}/backup.tar.gz"
    expect(response).to have_http_status(:not_found)
  end
end
