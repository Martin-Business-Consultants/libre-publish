# frozen_string_literal: true

# Foreign keys whose rows the app deletes while something still points at
# them. Without an ON DELETE, SQLite refuses the delete: a person who ever
# edited a page couldn't be deleted (their versions name them as author), a
# category entry still in use failed the nightly trash purge, and so did a
# collection another one used as its categories or tags. Each now lets go of
# what pointed at it (a version keeps its content and loses its author; an
# entry or page loses its category), and a device handshake goes with its
# person.
#
# SQLite can't alter a foreign key in place, so Rails rebuilds each table
# (copying its rows, indexes and the rest); none of them carries a trigger.
class SetOnDeleteForForeignKeys < ActiveRecord::Migration[8.1]
  KEYS = [
    [:page_versions, :users, :author_id, :nullify],
    [:collection_entry_versions, :users, :author_id, :nullify],
    [:collection_entries, :collection_entries, :category_entry_id, :nullify],
    [:pages, :collection_entries, :category_entry_id, :nullify],
    [:collections, :collections, :categories_collection_id, :nullify],
    [:collections, :collections, :tags_collection_id, :nullify],
    [:device_authorizations, :users, :user_id, :cascade]
  ].freeze

  def up
    KEYS.each do |from, to, column, on_delete|
      remove_foreign_key from, to, column: column
      add_foreign_key from, to, column: column, on_delete: on_delete
    end
  end

  def down
    KEYS.each do |from, to, column, _on_delete|
      remove_foreign_key from, to, column: column
      add_foreign_key from, to, column: column
    end
  end
end
