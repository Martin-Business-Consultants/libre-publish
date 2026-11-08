# frozen_string_literal: true

# Append-only snapshot of a Page's blocks. Written on every save where the
# blocks changed. Use for rollback and audit.
class PageVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[blocks].freeze

  snapshot_of :page
end
