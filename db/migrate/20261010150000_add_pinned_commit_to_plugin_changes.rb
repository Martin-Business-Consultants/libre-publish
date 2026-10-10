# frozen_string_literal: true

# A plugin installed or updated from the plugin directory: the commit the
# directory pinned, which is what's downloaded (PluginDirectory).
class AddPinnedCommitToPluginChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :plugin_changes, :pinned_commit, :string
  end
end
