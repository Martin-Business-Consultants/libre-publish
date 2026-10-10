# frozen_string_literal: true

# GET /api/v1/content[?since=<cursor>] — every live page, entry and global, or
# what changed since a previous read's cursor (ContentSnapshot). Pages need
# pages:read; entries and globals come only with entries:read and
# globals:read.
class Api::V1::ContentsController < Api::V1::BaseController
  requires_capability "pages:read", only: :show

  def show
    @snapshot = ContentSnapshot.new(since: ContentSnapshot.parse_cursor(params[:since]))
    @pages = @snapshot.pages
    # Entries and globals only for a token that reads them; the site's own
    # (Production site) reads all three.
    @readable = %w[entries globals].select { granted?("#{it}:read") }
    @entries = @readable.include?("entries") ? @snapshot.entries : []
    @globals = @readable.include?("globals") ? @snapshot.globals : []
    @removed = @snapshot.removed
    @removed = @removed.merge(entries: []) unless @readable.include?("entries")
    @removed = @removed.merge(globals: []) unless @readable.include?("globals")
    @assets = included_assets(pages: @pages, entries: @entries, globals: @globals)
    # What `data` renders from, for its cache (DeliveryVersion).
    @version = DeliveryVersion.current
    cache_tags("content")
    # The body carries the time it was read (meta.cursor), so its own digest
    # never repeats; a reader holding an answer built from the same content
    # gets 304 and keeps its cursor, still good since nothing changed after it.
    fresh_when etag: [@version, @snapshot.since&.iso8601(6), @readable, Digest::SHA256.hexdigest(@assets.to_json),
      request.headers["X-Agent-Envelope"]]
  end
end
