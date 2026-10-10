# frozen_string_literal: true

# An entry's saved versions (CollectionEntryVersion), newest first, each
# viewable as what restoring it would change.
class Collections::Entries::VersionsController < ApplicationController
  requires_capability "entries:read", only: [:index, :show]

  include EntryScoped

  def index
    @versions = paginate(@entry.versions.newest_first.includes(:author))
  end

  def show
    @version = @entry.versions.find(params[:id])
  end
end
