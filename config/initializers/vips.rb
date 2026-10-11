# frozen_string_literal: true

# libvips picks a decoder by what a file holds, not its name, and a system
# libvips may bring decoders (ImageMagick, PDF, MATLAB, FITS…) never meant for
# files strangers upload. Those it marks untrusted are turned off: uploads are
# photos and graphics (JPEG, PNG, WebP, GIF, HEIC, AVIF, TIFF, SVG).
begin
  require "vips"
  Vips.block_untrusted(true) if Vips.respond_to?(:block_untrusted)
rescue LoadError
  # No libvips here: images are served as uploaded.
end
