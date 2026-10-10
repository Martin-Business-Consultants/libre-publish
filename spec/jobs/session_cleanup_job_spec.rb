# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionCleanupJob do
  it "deletes ended sessions and keeps live ones" do
    user = create(:user)
    live = user.sessions.create!
    idle = user.sessions.create!
    idle.update_column(:last_seen_at, (Session::IDLE_TIMEOUT + 1.day).ago)

    described_class.perform_now

    expect(Session.where(id: [live.id, idle.id]).pluck(:id)).to eq([live.id])
  end
end
