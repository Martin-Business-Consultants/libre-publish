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

  it "runs once, even when its job runs twice" do
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
