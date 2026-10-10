# frozen_string_literal: true

# The delivery API, /api/v1: what a site reads to build and serve itself,
# read-only and frozen. It only ever shows what's live, whatever the token —
# a draft never reaches a site — and every answer has one shape:
#
#   {"data": …, "meta": {…}, "included": {"assets": {id => asset}}}
#
# `meta` carries paging on lists ({page, per, total, next_page}) and the
# cursor on /content; `included.assets` is every asset the records point at,
# resolved (MediaLibrary), when there's a media library. Each answer also
# names its cache tags (Cache-Tag), the ones a publish purges.
#
# /api stays the admin's and the CLI's: writes, drafts, management.
class Api::V1::BaseController < Api::BaseController
  enforce_authorization

  MAX_PER = 100

  # Per token, across the whole delivery API. A build reads it about ten
  # times; a site rendered on demand reads it on each Cloudflare cache miss,
  # so the default is generous. CMS_DELIVERY_RATE_LIMIT sets requests a
  # minute (0 turns it off).
  RATE_LIMIT = ENV.fetch("CMS_DELIVERY_RATE_LIMIT", "1200").to_i

  rate_limit to: RATE_LIMIT, within: 1.minute, scope: "api/v1", if: -> { RATE_LIMIT.positive? },
    by: -> { Current.api_token ? "#{Current.api_token.class.name}:#{Current.api_token.id}" : request.remote_ip },
    with: -> { render_rate_limited }

  private

  def paginate(scope)
    @page_number = params[:page].to_i.clamp(1, 100_000)
    @per = (params[:per].presence || 50).to_i.clamp(1, MAX_PER)
    @total = scope.count
    @meta = {page: @page_number, per: @per, total: @total,
             next_page: (@page_number + 1 if @page_number * @per < @total)}
    scope.offset((@page_number - 1) * @per).limit(@per)
  end

  # {id => asset} for the records, merged; nil without a media library.
  def included_assets(pages: [], entries: [], globals: [])
    return unless MediaLibrary.available?

    [MediaLibrary.resolve(:pages, pages), MediaLibrary.resolve(:entries, entries), MediaLibrary.resolve(:globals, globals)]
      .compact.reduce({}, :merge)
  end

  def cache_tags(*tags)
    response.headers["Cache-Tag"] = tags.flatten.compact.uniq.join(",")
  end
end
