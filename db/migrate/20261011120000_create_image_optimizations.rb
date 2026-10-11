# frozen_string_literal: true

# A run of the Media Library's Image Optimizer (ImageOptimization): how far
# it got, what it saved, and what it couldn't do.
class CreateImageOptimizations < ActiveRecord::Migration[8.1]
  def change
    create_table :image_optimizations do |t|
      t.string :status, null: false, default: "pending"
      t.integer :total, null: false, default: 0
      t.integer :processed, null: false, default: 0
      t.integer :optimized, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.integer :failed, null: false, default: 0
      t.bigint :bytes_before, null: false, default: 0
      t.bigint :bytes_after, null: false, default: 0
      t.json :errors_log, null: false, default: []
      t.bigint :user_id
      t.datetime :finished_at
      t.timestamps
    end
    add_index :image_optimizations, :status
  end
end
