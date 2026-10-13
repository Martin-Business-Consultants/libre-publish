# frozen_string_literal: true

# What browsers say a Content-Security-Policy blocked (or would, in report
# only): one row per surface, directive and source, counted, so Settings ›
# Security policy can offer to allow it.
class CreateCspReports < ActiveRecord::Migration[8.1]
  def change
    create_table :csp_reports do |t|
      t.string :surface, null: false
      t.string :directive, null: false
      t.string :blocked, null: false
      t.string :page
      t.integer :count, null: false, default: 1
      t.datetime :last_seen_at, null: false
      t.boolean :dismissed, null: false, default: false
      t.timestamps
    end
    add_index :csp_reports, [:surface, :directive, :blocked], unique: true
  end
end
