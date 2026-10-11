# frozen_string_literal: true

# Making an image lighter: a JPEG, PNG or WebP over the site's limits
# (ImageLimits, Settings › Media) — its file size, or its longest side —
# becomes a WebP within them, in place: the asset keeps its id, so everything
# that uses it carries on, and the file it had is kept (original_file) to put
# back (restore_original!). Done as it's uploaded (LightenJob), and by the
# Media Library's Image Optimizer (ImageOptimization) for the images already
# there.
#
# A WebP at the longest side allowed comes first; while it's still over the
# file size, the quality steps down, then the size, to no less than
# MIN_STEP_SIDE across. A result that's still over and doesn't save at least
# a tenth isn't kept. GIFs and animated WebPs (which move) and SVGs (vector)
# are left alone.
module Asset::Optimizable
  extend ActiveSupport::Concern

  OPTIMIZABLE_TYPES = %w[image/jpeg image/png image/webp].freeze
  # As a zip's images are made WebPs (BulkUpload::Unpackable), then lower
  # while the file is still over the limit.
  QUALITIES = [85, 75, 65].freeze
  # Each further step down in size, and how small that goes.
  SIDE_STEPS = [0.8, 0.64, 0.5].freeze
  MIN_STEP_SIDE = 1280
  MAX_PIXELS = 100_000_000
  MIN_SAVING = 0.1

  included do
    has_one_attached :original_file
  end

  class_methods do
    # Images the optimizer would look at.
    def optimizable_candidates
      with_attached_file.joins(file_attachment: :blob)
        .where(active_storage_blobs: {content_type: OPTIMIZABLE_TYPES}).where(deleted_at: nil)
    end
  end

  # Whether it's an image the optimizer would make lighter.
  def optimizable?
    return false unless file.attached? && content_type.in?(OPTIMIZABLE_TYPES)

    width, height = file.metadata.values_at("width", "height").map(&:to_i)
    byte_size > ImageLimits.max_bytes || [width, height].max > ImageLimits.max_side
  end

  def optimized? = original_file.attached?

  # Makes it a lighter WebP; returns [bytes before, bytes after], or nil when
  # that wouldn't help.
  def optimize!
    before = byte_size
    max_bytes = ImageLimits.max_bytes
    file.open do |source|
      header = Vips::Image.new_from_file(source.path)
      if header.width * header.height > MAX_PIXELS
        raise ArgumentError, "#{header.width} × #{header.height} pixels is more than the optimizer reads."
      end
      return nil if header.get_typeof("n-pages").positive? && header.get("n-pages") > 1

      out = lightest_within(source.path, [header.width, header.height].max, max_bytes)
      after = out.size
      return nil if after > max_bytes && after > before * (1 - MIN_SAVING)

      transaction do
        source.rewind
        original_file.attach(io: source, filename: filename, content_type: content_type) unless optimized?
        file.attach(io: File.open(out, "rb"), filename: "#{File.basename(filename.to_s, ".*")}.webp", content_type: "image/webp")
      end
      [before, after]
    ensure
      out&.close!
    end
  end

  # The file it had before it was optimized, back in place.
  def restore_original!
    return false unless optimized?

    transaction do
      original = original_file.blob
      file.attach(original)
      original_file.detach
    end
    true
  end

  private

  # The first WebP of the steps (QUALITIES at the longest side allowed, then
  # SIDE_STEPS smaller) that's within max_bytes, or the last, the lightest.
  def lightest_within(path, longest, max_bytes)
    side = [longest, ImageLimits.max_side].min
    floor = [side, MIN_STEP_SIDE].min
    steps = QUALITIES.map { [side, it] } +
      SIDE_STEPS.map { [(side * it).round, QUALITIES.last] }.select { |step_side, _| step_side >= floor }.uniq
    out = nil
    steps.each do |step_side, quality|
      out&.close!
      out = ImageProcessing::Vips.source(path).resize_to_limit(step_side, step_side)
        .convert("webp").saver(quality: quality, strip: true).call
      break if out.size <= max_bytes
    end
    out
  end

  def lighten_on_upload? = file.attached? && content_type.in?(OPTIMIZABLE_TYPES) && ImageLimits.optimize_uploads?

  def lighten_later = Asset::LightenJob.perform_later(id)
end
