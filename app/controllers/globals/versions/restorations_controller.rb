# frozen_string_literal: true

# "Restore this version" of a global: its name and data go back through the
# editor's own save, so it takes what an edit takes (globals:publish, and
# globals:scripts for the Scripts global).
class Globals::Versions::RestorationsController < ApplicationController
  requires_capability "globals:write", only: :create

  include ContentEditing
  include GlobalScriptsGuard

  before_action { @global = Global.find_by!(slug: params[:global_slug]) }
  before_action :guard_scripts_global!

  def create
    version = @global.versions.find(params[:version_id])
    if save_content(@global, version.snapshot, prefix: "globals")
      @global.track_update
      redirect_to edit_global_path(@global.slug), notice: "Version restored"
    else
      redirect_to global_version_path(@global.slug, version), alert: @global.errors.full_messages.to_sentence
    end
  end
end
