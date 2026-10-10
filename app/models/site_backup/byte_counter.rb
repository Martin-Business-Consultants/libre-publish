# frozen_string_literal: true

# The IO a backup's gzip stream writes through: passes every write on to the
# real IO and counts the bytes. Closing it (Zlib::GzipWriter.wrap does, when
# it finishes) leaves the real IO open, so a caller can rewind and read what
# was written.
class SiteBackup::ByteCounter
  attr_reader :bytes

  def initialize(io)
    @io = io
    @bytes = 0
  end

  def write(*chunks)
    written = @io.write(*chunks)
    @bytes += written
    written
  end

  def flush
    @io.flush if @io.respond_to?(:flush)
    self
  end

  def close
    flush
    nil
  end
end
