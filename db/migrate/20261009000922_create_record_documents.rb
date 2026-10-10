# frozen_string_literal: true

# The admin's search index (config/search.rb's :records, ActiveSearch): a row
# per searchable record and an FTS5 table of their text, trigram so a search
# finds any part of a word. It replaces pages_fts and collection_entries_fts,
# and is filled from what's already here (an install updating, or a site
# imported from the old deployment).
class CreateRecordDocuments < ActiveRecord::Migration[8.1]
  def up
    create_table :record_documents do |t|
      t.string :record_type, null: false
      t.string :record_id, null: false
    end
    add_index :record_documents, [:record_type, :record_id], unique: true
    create_virtual_table :record_documents_fts, :fts5, ["title", "body", "tokenize='trigram'"]

    drop_table :pages_fts, if_exists: true
    drop_table :collection_entries_fts, if_exists: true

    say_with_time("Indexing what's here for search") { SearchIndexed.reindex_all }
  end

  def down
    drop_table :record_documents_fts, if_exists: true
    drop_table :record_documents, if_exists: true
    create_virtual_table :pages_fts, :fts5, ["slug UNINDEXED", "title", "body", "tokenize = 'porter'"]
    create_virtual_table :collection_entries_fts, :fts5, ["slug UNINDEXED", "collection_slug UNINDEXED", "title", "body", "tokenize = 'porter'"]
  end
end
