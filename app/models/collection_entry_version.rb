# frozen_string_literal: true

# Append-only snapshot of a CollectionEntry's frontmatter + body_markdown.
class CollectionEntryVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[frontmatter body_markdown blocks].freeze

  snapshot_of :collection_entry
end
