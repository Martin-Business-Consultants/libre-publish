# frozen_string_literal: true

# GET /api/redirects/resolve?path=/foo — which rule a request path lands on,
# counted as a hit. Capability-free, like the edge payload.
class Api::Redirects::ResolutionsController < Api::BaseController
  # Where a path redirects: what any visitor finds out by asking the site.
  skip_authorization only: :show

  def show
    @match = Redirect.resolve(params[:path])
  end
end
