# frozen_string_literal: true

# Append-only snapshot of a Global: its name and data (navigation items, the
# footer's columns, the scripts), written on every save that changes either.
# Compared and restored as a page's versions are (VersionSnapshot).
class GlobalVersion < ApplicationRecord
  include VersionSnapshot

  SNAPSHOT_ATTRIBUTES = %w[name data].freeze

  snapshot_of :global
end
