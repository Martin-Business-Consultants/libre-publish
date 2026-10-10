# frozen_string_literal: true

# A built backup as a Rack response body: read back from its temporary file
# in chunks as the response is sent, and the file deleted once it has been
# (or the client went away).
class SiteBackup::Download
  CHUNK = 64 * 1024

  def initialize(file)
    @file = file
  end

  def bytesize = @file.size

  def each
    while (chunk = @file.read(CHUNK))
      yield chunk
    end
  end

  def close
    @file.close unless @file.closed?
    File.delete(@file.path) if File.exist?(@file.path)
  end
end
