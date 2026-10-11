# frozen_string_literal: true

# One run of the Media Library's Image Optimizer: every image over the
# optimizer's limits made a lighter WebP (Asset::Optimizable), in the
# background (ImageOptimization::RunJob), counted as it goes for the page
# that follows it (file_manager/image_optimizations#show). One at a time.
class ImageOptimization < ApplicationRecord
  STATUSES = %w[pending running succeeded partial failed].freeze

  class Busy < StandardError; end

  validates :status, inclusion: {in: STATUSES}

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :unfinished, -> { where(status: %w[pending running]) }

  def self.current = unfinished.recent.first

  def self.start(user: Current.user)
    raise Busy, "The optimizer is already running." if current

    optimization = create!(status: "pending", user_id: user&.id)
    ImageOptimization::RunJob.perform_later(optimization.id)
    Event.record("assets.optimization_started", target: optimization)
    optimization
  end

  # Claims the run first, so a job that runs twice (a retry) does it once.
  def run
    return unless self.class.where(id: id, status: "pending").update_all(status: "running", updated_at: Time.current) == 1

    reload
    assets = Asset.optimizable_candidates.select(&:optimizable?)
    update!(total: assets.size)
    assets.each { optimize(it) }
    update!(status: failed.zero? ? "succeeded" : "partial", finished_at: Time.current)
  rescue StandardError => e
    update_columns(status: "failed", finished_at: Time.current, errors_log: errors_log + [{"filename" => "", "message" => e.message}])
    raise
  end

  def finished? = status.in?(%w[succeeded partial failed])

  def progress = total.zero? ? (finished? ? 100 : 0) : (processed * 100.0 / total).round

  def bytes_saved = bytes_before - bytes_after

  private

  def optimize(asset)
    if (sizes = asset.optimize!)
      increment_counts(optimized: 1, bytes_before: sizes.first, bytes_after: sizes.last)
    else
      increment_counts(skipped: 1)
    end
  rescue StandardError => e
    raise if e.is_a?(ActiveRecord::ConnectionNotEstablished)

    self.errors_log = errors_log + [{"filename" => asset.filename.to_s, "message" => e.message}]
    increment_counts(failed: 1)
  end

  def increment_counts(**by)
    by.each { |column, amount| self[column] += amount }
    self.processed += 1
    save!(validate: false)
  end
end
