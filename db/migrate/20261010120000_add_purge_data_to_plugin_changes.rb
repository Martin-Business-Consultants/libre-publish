# frozen_string_literal: true

# A plugin removed with its data: its tables dropped too (PluginChange#purge).
class AddPurgeDataToPluginChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :plugin_changes, :purge_data, :boolean, default: false, null: false
  end
end
