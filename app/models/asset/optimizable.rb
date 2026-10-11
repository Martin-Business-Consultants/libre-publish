# frozen_string_literal: true

# Making an image lighter (the Media Library's Image Optimizer,
# ImageOptimization): a JPEG, PNG or WebP over OVER_BYTES, or wider or taller
# than MAX_SIDE, becomes a WebP at most MAX_SIDE pixels across, in place: the
# asset keeps its id, so everything that uses it carries on, and the file it
# had is kept (original_file) to put back (restore_original!). A result that
# doesn't save at least a tenth isn't kept. GIFs (which may move) and SVGs
# (vector) are left alone.
module Asset::Optimizable
  extend ActiveSupport::Concern

  OPTIMIZABLE_TYPES = %w[image/jpeg image/png image/webp].freeze
  OVER_BYTES = 500.kilobytes
  MAX_SIDE = 2560
  # As a zip's images are made WebPs (BulkUpload::Unpackable).
  QUALITY = 85
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
    byte_size > OVER_BYTES || [width, height].max > MAX_SIDE
  end

  def optimized? = original_file.attached?

  # Makes it a lighter WebP; returns [bytes before, bytes after], or nil when
  # that wouldn't save enough.
  def optimize!
    before = byte_size
    file.open do |source|
      header = Vips::Image.new_from_file(source.path)
      if header.width * header.height > MAX_PIXELS
        raise ArgumentError, "#{header.width} × #{header.height} pixels is more than the optimizer reads."
      end

      out = ImageProcessing::Vips.source(source.path).resize_to_limit(MAX_SIDE, MAX_SIDE)
        .convert("webp").saver(quality: QUALITY, strip: true).call
      after = File.size(out)
      return nil if after > before * (1 - MIN_SAVING)

      transaction do
        source.rewind
        original_file.attach(io: source, filename: filename, content_type: content_type) unless optimized?
        file.attach(io: File.open(out, "rb"), filename: "#{File.basename(filename.to_s, ".*")}.webp", content_type: "image/webp")
      end
      [before, after]
    ensure
      File.delete(out) if out && File.exist?(out)
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
end
