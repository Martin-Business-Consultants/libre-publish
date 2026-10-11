# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The Image Optimizer", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }
  let(:reader) { create(:user, admin: false, role: create(:role, permissions: %w[assets:read])) }

  it "is a button on the Media Library that starts a run in the background and follows it" do
    sign_in_as admin
    get file_manager_path
    expect(response.body).to include("Image Optimizer")

    expect { post file_manager_image_optimizations_path }.to have_enqueued_job(ImageOptimization::RunJob)
    run = ImageOptimization.last
    expect(response).to redirect_to(file_manager_image_optimization_path(run))

    follow_redirect!
    expect(response.body).to include("images looked at", %(data-controller="refresh"))

    get file_manager_path
    expect(response.body).to include("Optimizing images…")

    post file_manager_image_optimizations_path
    expect(ImageOptimization.count).to eq(1)
  end

  it "puts an optimized image's original back from its details" do
    asset = Asset.create!(folder: "/", file: {io: StringIO.new("WEBP"), filename: "hero.webp", content_type: "image/webp"})
    asset.original_file.attach(io: StringIO.new("PNG" * 100), filename: "hero.png", content_type: "image/png")
    sign_in_as admin

    get file_manager_asset_path(asset)
    expect(response.body).to include("Restore original", "optimized from")

    post file_manager_asset_restoration_path(asset)
    expect(asset.reload.filename.to_s).to eq("hero.png")
    expect(asset).not_to be_optimized
  end

  it "isn't offered to someone who can't change the library" do
    sign_in_as reader
    get file_manager_path
    expect(response.body).not_to include("Image Optimizer")

    post file_manager_image_optimizations_path
    expect(ImageOptimization.count).to eq(0)
  end
end
