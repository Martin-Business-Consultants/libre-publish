# frozen_string_literal: true

# "Restore this version": the version's fields, body and blocks go back
# through the editor's own save, so restoring over a live entry needs the
# publish capability, as any other edit would.
class Collections::Entries::Versions::RestorationsController < ApplicationController
  requires_capability "entries:write", only: :create

  include EntryScoped
  include ContentEditing

  def create
    version = @entry.versions.find(params[:version_id])
    prior_status = @entry.status
    if save_content(@entry, version.snapshot, prefix: "entries")
      @entry.track_update(from: prior_status)
      redirect_to edit_collection_entry_path(@collection.slug, @entry.slug), notice: "Version restored"
    else
      redirect_to collection_entry_version_path(@collection.slug, @entry.slug, version), alert: @entry.errors.full_messages.to_sentence
    end
  end
end
