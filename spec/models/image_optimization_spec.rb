# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe ImageOptimization do
  include ActiveJob::TestHelper

  # A photo-like PNG: noise doesn't compress, so it's large.
  def png(width, height)
    path = Rails.root.join("tmp", "optimizer-#{width}x#{height}-#{SecureRandom.hex(4)}.png").to_s
    Vips::Image.gaussnoise(width, height, mean: 128, sigma: 40).cast(:uchar).bandjoin([Vips::Image.gaussnoise(width, height).cast(:uchar)] * 2).write_to_file(path)
    path
  end

  def asset_from(path, name:, content_type: "image/png")
    Asset.create!(folder: "/", name: name, file: {io: File.open(path), filename: File.basename(path), content_type: content_type}).tap do
      it.file.analyze
    end
  end

  it "makes the large images lighter WebPs in place, keeps their originals, and leaves the rest" do
    ImageLimits.update("max_kb" => 10_000, "max_side" => 2560, "optimize_uploads" => false)
    big = asset_from(png(3000, 1800), name: "Hero")
    small = asset_from(png(40, 40), name: "Icon")
    svg = Asset.create!(folder: "/", name: "Logo", file: {io: File.open(Rails.root.join("public/icon.svg")), filename: "icon.svg", content_type: "image/svg+xml"})
    big_before = big.byte_size

    run = described_class.start
    perform_enqueued_jobs
    run.reload

    expect(run).to have_attributes(status: "succeeded", total: 1, processed: 1, optimized: 1, failed: 0)
    expect(run.bytes_saved).to be_positive

    big.reload
    big.file.analyze
    expect(big).to have_attributes(content_type: "image/webp", name: "Hero")
    expect(big.filename.to_s).to end_with(".webp")
    expect([big.file.metadata["width"], big.file.metadata["height"]].max).to eq(2560)
    expect(big.byte_size).to be < big_before
    expect(big.original_file.byte_size).to eq(big_before)

    expect(small.reload.content_type).to eq("image/png")
    expect(svg.reload.content_type).to eq("image/svg+xml")

    big.restore_original!
    expect(big.reload).to have_attributes(content_type: "image/png", byte_size: big_before)
    expect(big).not_to be_optimized
  end

  it "steps the quality, then the size, down while an image is still over the site's file size" do
    ImageLimits.update("max_kb" => 400, "max_side" => 2560, "optimize_uploads" => false)
    noisy = asset_from(png(3000, 1800), name: "Noise")

    before, after = noisy.optimize!
    noisy.reload.file.analyze

    expect(after).to be < before
    expect([noisy.file.metadata["width"], noisy.file.metadata["height"]].max).to be_between(Asset::Optimizable::MIN_STEP_SIDE, 2047)
  end

  it "makes an upload over the limits lighter as it arrives, unless the site turns that off" do
    upload = ->(name) { Asset.create!(folder: "/", name: name, file: {io: File.open(png(3000, 1800)), filename: "#{name}.png", content_type: "image/png"}) }

    perform_enqueued_jobs { upload.("Hero") }
    expect(Asset.find_by!(name: "Hero")).to have_attributes(content_type: "image/webp", optimized?: true)

    ImageLimits.update("optimize_uploads" => false)
    perform_enqueued_jobs { upload.("Banner") }
    expect(Asset.find_by!(name: "Banner").content_type).to eq("image/png")
  end

  it "runs once, even when its job runs twice" do
    ImageLimits.update("optimize_uploads" => false)
    asset_from(png(3000, 1800), name: "Hero")
    run = described_class.start
    2.times { run.reload.run }

    expect(run.reload).to have_attributes(total: 1, processed: 1, optimized: 1)
  end

  it "runs one at a time" do
    described_class.start
    expect { described_class.start }.to raise_error(ImageOptimization::Busy)
  end
end
