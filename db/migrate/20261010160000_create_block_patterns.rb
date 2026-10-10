# frozen_string_literal: true

# Patterns: a saved set of blocks, inserted into a page or entry as a copy,
# or (synced) as a "pattern" block that always shows the pattern's blocks.
class CreateBlockPatterns < ActiveRecord::Migration[8.1]
  def up
    create_table :block_patterns do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: {unique: true}
      t.text :description
      t.json :blocks, null: false, default: []
      t.boolean :synced, null: false, default: false
      t.timestamps
    end

    # The block a synced pattern is placed with.
    BlockType::Defaults.install!([BlockType::Defaults::PATTERN]) if table_exists?(:block_types)
  end

  def down
    drop_table :block_patterns
    execute "DELETE FROM block_types WHERE slug = 'pattern' AND built_in = 1"
  end
end
