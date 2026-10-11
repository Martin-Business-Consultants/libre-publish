# frozen_string_literal: true

# Version history for globals (navigation, footer, scripts…) and for the
# settings people edit (GlobalVersion, SettingVersion), as pages and entries
# have had: every change kept, compared and restorable.
class CreateGlobalAndSettingVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :global_versions do |t|
      t.references :global, null: false, foreign_key: {on_delete: :cascade}
      t.integer :author_id, index: true
      t.string :name
      t.json :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :global_versions, [:global_id, :created_at]

    create_table :setting_versions do |t|
      t.references :setting, null: false, foreign_key: {on_delete: :cascade}
      t.string :key, null: false
      t.integer :author_id, index: true
      t.json :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :setting_versions, [:setting_id, :created_at]
  end
end
