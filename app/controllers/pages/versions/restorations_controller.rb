# frozen_string_literal: true

# "Restore this version": the version's blocks go back through the editor's
# own save, so restoring over live content needs the publish capability, as
# any other edit would.
class Pages::Versions::RestorationsController < ApplicationController
  requires_capability "pages:write", only: :create

  include PageScoped
  include ContentEditing

  def create
    version = @page.versions.find(params[:version_id])
    prior_status = @page.status
    if save_content(@page, version.snapshot, prefix: "pages")
      @page.track_update(from: prior_status)
      redirect_to edit_page_path(@page.path), notice: "Version restored"
    else
      redirect_to page_version_path(@page.path, version), alert: @page.errors.full_messages.to_sentence
    end
  end
end
