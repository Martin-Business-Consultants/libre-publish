# frozen_string_literal: true

class CreatePluginChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_changes do |t|
      t.references :requested_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.string :key
      t.string :repo, null: false
      t.string :action, null: false
      t.string :from_version
      t.string :to_version
      t.string :status, null: false, default: "running"
      t.text :message
      t.datetime :finished_at
      t.timestamps
    end
    add_index :plugin_changes, :status
  end
end
