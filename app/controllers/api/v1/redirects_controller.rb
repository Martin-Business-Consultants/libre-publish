# frozen_string_literal: true

# GET /api/v1/redirects — the active rules; /api/v1/redirects.txt — the same
# as a Cloudflare _redirects file: exact rules first, then wildcards longest
# first (Cloudflare takes the first match, as Redirect.match does), a
# wildcard's tail carried over as :splat.
class Api::V1::RedirectsController < Api::V1::BaseController
  requires_capability "redirects:read", only: :index

  def index
    exact, wildcards = Redirect.active.order(:source_path).partition { !it.wildcard }
    @redirects = exact + wildcards.sort_by { -it.source_path.length }
    cache_tags("redirects")
    respond_to do |format|
      format.json
      format.text
    end
  end
end
