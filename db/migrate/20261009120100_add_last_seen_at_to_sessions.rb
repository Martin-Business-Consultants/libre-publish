# frozen_string_literal: true

# When a session was last used, so an idle one can expire (Session::IDLE_TIMEOUT).
class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :last_seen_at, :datetime
    execute "UPDATE sessions SET last_seen_at = updated_at"
  end

  def down
    remove_column :sessions, :last_seen_at
  end
end
