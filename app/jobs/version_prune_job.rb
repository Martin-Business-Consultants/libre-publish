# frozen_string_literal: true

# Nightly: keeps the newest CMS_VERSIONS_KEEP (100) versions of each page and
# entry, and deletes the rest (VersionSnapshot.prune).
class VersionPruneJob < ApplicationJob
  queue_as :default

  def perform
    PageVersion.prune
    CollectionEntryVersion.prune
  end
end
