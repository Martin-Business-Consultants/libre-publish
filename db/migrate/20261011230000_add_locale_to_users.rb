# frozen_string_literal: true

# The language a person's admin is in (AdminLocale); nil follows the
# workspace's (Settings › General).
class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string
  end
end
