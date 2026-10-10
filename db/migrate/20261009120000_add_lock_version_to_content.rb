# frozen_string_literal: true

# Optimistic locking for what editors change (Active Record's lock_version):
# a save made from a page, entry or global as it was read fails, rather than
# overwriting a change someone saved in between, when the editor's form or
# API call says which version it read.
class AddLockVersionToContent < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :lock_version, :integer, default: 0, null: false
    add_column :collection_entries, :lock_version, :integer, default: 0, null: false
    add_column :globals, :lock_version, :integer, default: 0, null: false
  end
end
