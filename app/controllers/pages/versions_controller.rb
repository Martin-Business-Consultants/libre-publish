# frozen_string_literal: true

# A page's saved versions (PageVersion), newest first, each viewable as what
# restoring it would change.
class Pages::VersionsController < ApplicationController
  requires_capability "pages:read", only: [:index, :show]

  include PageScoped

  def index
    @versions = paginate(@page.versions.newest_first.includes(:author))
  end

  def show
    @version = @page.versions.find(params[:id])
  end
end
