# frozen_string_literal: true

# A global's saved versions (GlobalVersion), newest first, each viewable as
# what restoring it would change.
class Globals::VersionsController < ApplicationController
  requires_capability "globals:read", only: [:index, :show]

  before_action { @global = Global.find_by!(slug: params[:global_slug]) }

  def index
    @versions = paginate(@global.versions.newest_first.includes(:author))
  end

  def show
    @version = @global.versions.find(params[:id])
  end
end
