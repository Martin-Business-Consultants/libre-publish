# frozen_string_literal: true

# The last two-factor code a person used, as its 30-second step, so the same
# code (seen over a shoulder, or replayed) can't be used again.
class AddTotpLastCounterToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_last_counter, :bigint
  end
end
