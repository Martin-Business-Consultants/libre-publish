# frozen_string_literal: true

# A saved version of a page or an entry (PageVersion, CollectionEntryVersion):
# what it holds, and what restoring it would change on the record now, as a
# ContentDiff.
#
# Versions are kept per record up to a limit (CMS_VERSIONS_KEEP, 100 by
# default), the newest first: the nightly VersionPruneJob deletes the rest,
# so a page saved every few minutes for years doesn't carry every one.
module VersionSnapshot
  extend ActiveSupport::Concern

  DEFAULT_KEEP = 100

  class_methods do
    # How many versions of each record to keep.
    def keep_limit(env = ENV)
      limit = env["CMS_VERSIONS_KEEP"].to_s.strip
      limit.match?(/\A\d+\z/) && limit.to_i.positive? ? limit.to_i : DEFAULT_KEEP
    end

    # Deletes every version beyond the newest `keep` of its record, in one
    # statement. Returns how many went.
    def prune(keep: keep_limit)
      owner = reflect_on_association(versioned_association).foreign_key
      beyond = select(:id).from(
        select(:id, sanitize_sql_array(["ROW_NUMBER() OVER (PARTITION BY #{connection.quote_column_name(owner)} ORDER BY created_at DESC, id DESC) AS position"]))
          .arel.as(table_name)
      ).where("position > ?", keep)
      where(id: beyond).delete_all
    end
  end

  # The attributes this version holds, as the record would take them back.
  def snapshot
    self.class::SNAPSHOT_ATTRIBUTES.index_with { public_send(it) }
  end

  # Only the attributes that differ from the record now.
  def changes_from_current
    current = versioned_record.slice(*self.class::SNAPSHOT_ATTRIBUTES)
    changed = snapshot.reject { |key, value| ContentDiff.normalize(value) == ContentDiff.normalize(current[key]) }
    ContentDiff.new(changed, current).call
  end

  def matches_current?
    changes_from_current[:fields].empty?
  end
end
